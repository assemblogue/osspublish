# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader'
require 'zip'
require 'tempfile'
require 'thwait'
require 'logger'
require 'roo'
require 'digest'
require 'open3'
require 'securerandom'
require 'pp'
require './gen_com'

# Limits against overload
# See also http_content_length_limit in config/puma.rb
COMMAND_TIMEOUT_SECONDS = 15
MAX_FILES = 10

def spreadsheet_to_csv(path, tmpdir)
  begin
    xlsx = Roo::Spreadsheet.open(path)
    fpath = File.join(tmpdir, "#{File.basename(path)}#{SecureRandom.hex}.csv")
    return File.open(fpath, 'w') do |f|
      f.write(xlsx.to_csv)
      f.path
    end
  rescue ArgumentError
  end
  path
end

# Runs the command in a thread. The thread's value is one of:
#   nil                                    exit 0 with no stderr
#   { command:, exit_status: 0, message: } exit 0 with stderr (a warning)
#   { command:, exit_status:, message: }   non-zero exit, or nil if it could not run
# The command is killed after `timeout` seconds (coreutils timeout: exit status 124).
def run_command_async(command, logger, stdin_data: nil, timeout: COMMAND_TIMEOUT_SECONDS)
  cmd = command.join(' ')

  Thread.new do
    logger.info { "Command: #{cmd}" }
    stdout, stderr, status = Open3.capture3('timeout', '-k', '5', timeout.to_s, *command, stdin_data:)
    logger.debug { "Stdout: #{stdout}" }
    logger.info { "Stderr: #{stderr}" } unless stderr.empty?

    message = status.exitstatus == 124 ? "timed out after #{timeout} seconds" : stderr.strip
    { command: cmd, exit_status: status.exitstatus, message: } unless status.success? && stderr.strip.empty?
  rescue StandardError => e
    logger.error { "Command failed: #{cmd}: #{e.full_message}" }

    { command: cmd, exit_status: nil, message: "#{e.class}: #{e.message}" }
  end
end

# Converts one uploaded file.
# Returns { file:, error: [...], warning: [...], outputs: [path, ...] }.
# error and warning entries are { command:, exit_status:, message: }
def convert_file(file, tmpdir, logger)
  tempfile = file[:tempfile]
  filename = File.basename(file[:filename].to_s.empty? ? tempfile.path : file[:filename])

  logger.info("#{filename}: #{tempfile.path}: #{tempfile.size} bytes")

  csv_contents = File.binread(spreadsheet_to_csv(tempfile.path, tmpdir))
  base = File.join(tmpdir, File.basename(tempfile.path, '.csv'))

  warnings, errors = [
    run_command_async(['perl', 'plrv2/contentsdata/cto/cto.pl', base, ''], logger, stdin_data: csv_contents),
    run_command_async(['perl', 'plrv2/contentsdata/cto/cts.pl', base, ''], logger, stdin_data: csv_contents)
  ].filter_map(&:value).partition { |result| result[:exit_status] == 0 }

  outputs = if errors.empty?
              Dir.glob("#{base}*.jsonld")
                 .reject { |path| path =~ /(Context|_stylesheet)\.jsonld$/ }
            else
              []
            end

  { file: filename, error: errors, warning: warnings, outputs: }
rescue StandardError => e
  logger.error { "Conversion failed: #{e.full_message}" }

  { file: filename || 'unknown', error: [{ message: "#{e.class}: #{e.message}" }], warning: [], outputs: [] }
end

# proxy IO for multiple IOs
class MultiIO
  def initialize(*targets)
    @targets = targets
  end

  def write(*args)
    @targets.each { |t| t.write(*args) }
  end

  def flush
    @targets.each(&:flush)
  end

  def close
    @targets.each(&:close)
  end
end

# main class App
class App < Sinatra::Base
  disable :sessions

  configure do
    set :server, :puma
  end

  configure do
    register Sinatra::Reloader unless production?
  end

  get '/' do
    erb :form, locals: {
          env: settings.environment
        }
  end

  post '/convert' do
    # Uploaded files are hashes, sent as `file[]` (an array) or as a single `file`.
    files = [params['file']].flatten.grep(Hash)
    halt 400, 'No files uploaded' if files.empty?
    halt 400, "Too many files (max #{MAX_FILES})" if files.size > MAX_FILES

    # The tmp dir for intermediate files will be removed when this block ends
    zip_data = Dir.mktmpdir do |tmpdir|
      logfile = File.join(tmpdir, 'log.txt')
      zip = File.join(tmpdir, 'converted.zip')
      puts "Running #{settings.environment}, logging in #{logfile}"

      logfile_file = File.open(logfile, 'w')
      logfile_io = settings.environment == :test ? MultiIO.new(STDERR, logfile_file) : logfile_file
      logger = Logger.new(logfile_io).tap do |x|
        x.level = if settings.environment == :production
                    Logger::INFO
                  else
                    Logger::DEBUG
                  end
      end

      logger.debug { request.env.inspect }
      logger.info("Reading #{files.inspect}")

      Zip::File.open(zip, create: true) do |zipfile|
        index = {}
        results = files.map { |file| convert_file(file, tmpdir, logger) }

        results.each do |result|
          result[:outputs].each do |path|
            zfilename = File.basename(path)
            logger.info("Adding #{path} (from #{result[:file]})")
            zipfile.add(zfilename, path)
            zipfile.commit

            get_link_and_label(path) do |link, label, base|
              if base.empty?
                logger.warn("Not linking #{path}")
              else
                index[link] ||= []
                index[link] << { file: zfilename, label: label, id: base, format: 'application/ld+json' }
              end
            end
          rescue StandardError => e
            logger.error { "Cannot add #{path} (from #{result[:file]}): #{e.message}" }
            result[:error] << { message: "#{e.class}: #{e.message}" }
          end
        end

        index[:response] = results.map { |result| result.slice(:file, :error, :warning) }

        Tempfile.create('tmp') do |file|
          file.puts(index.to_json)
          file.flush
          logfile_io.flush

          zipfile.add('index.json', file)
          zipfile.add('log.txt', logfile)
          zipfile.commit
        end
      end

      File.binread(zip)
    ensure
      logfile_file&.close
    end

    attachment "converted-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4)}.zip"
    zip_data
  end

  get '/env' do
    content_type 'text/plain'
    unless settings.environment == :production
      <<~RETURN
        #{ENV.pretty_inspect}

        #{self.pretty_inspect}
      RETURN
    end
  end
end
