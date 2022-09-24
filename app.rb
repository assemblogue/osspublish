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

def run_command_async(command, logger)
  Thread.new do
    logger.info("Running command: #{command}")
    stdout, stderr, status = Open3.capture3(command)
    unless status.success?
      logger.info("Stdout: #{stdout}")
      logger.info("Stderr: #{stderr}")
    end
    logger.info("Finishing: #{command}")
    yield if block_given?
  end
end

def JSONize(files, tmpdir, logger)
  threads = files.map do |f|
    logger.info("#{f.path}: #{f.size} bytes, #{Digest::MD5.hexdigest(f.read)}")
    base = File.join(tmpdir, File.basename(f, '.csv'))
    [run_command_async("cat #{spreadsheet_to_csv(f.path, tmpdir)} | perl plrv2/contentsdata/cto/cto.pl #{base} ''", logger),
     run_command_async("cat #{spreadsheet_to_csv(f.path, tmpdir)} | perl plrv2/contentsdata/cto/cts.pl #{base} ''", logger)]
  end.flatten
  ThreadsWait.all_waits(*threads)

  Dir.glob("#{tmpdir}/*.jsonld")
     .reject { |f| f =~ /(Context|_stylesheet)\.jsonld$/ }
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
    logfile = Tempfile.create(['log', '.txt']).path
    puts "Running #{settings.environment}, logging in #{logfile}"
    logfile_io = if settings.environment == :test
                   MultiIO.new(STDERR, File.open(logfile, 'a'))
                 else
                   File.open(logfile, 'w')
                 end
    logger = Logger.new(logfile_io).tap do |x|
      x.level = if settings.environment == :production
                  Logger::INFO
                else
                  Logger::DEBUG
                end
    end

    files = request.env['rack.tempfiles']
    logger.debug(request.env.inspect)
    zip = Tempfile.create(['converted', '.zip']).path
    logger.info("Reading #{files.inspect}")
    Dir.mktmpdir do |tmpdir|
      Zip::File.open(zip, Zip::File::CREATE) do |zipfile|
        index = {}
        JSONize(files, tmpdir, logger).each do |path|
          logger.info("Adding #{path}")
          zipfile.add(File.basename(path), path)
          zipfile.commit
          get_link_and_label(path) do |link, label, base|
            if base == ''
              logger.warn("Not linking #{path}")
            else
              index[link] ||= []
              index[link] << {
                'file' => File.basename(path),
                'label' => label,
                'id' => base,
                'format' => 'application/ld+json'
              }
            end
          end
        end
        Tempfile.create('tmp') do |f|
          f.puts index.to_json
          f.flush
          logfile_io.flush
          zipfile.add('index.json', f)
          zipfile.add('log.txt', logfile)
          zipfile.commit
          send_file(zip, filename: File.basename(zip))
        end
      end
    end
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
