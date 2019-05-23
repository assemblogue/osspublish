require 'sinatra'
require 'sinatra/reloader' if development?
require 'zip'
require 'tempfile'
require 'thwait'
require 'logger'
require 'roo'
require 'securerandom'
require './gen_com'

def spreadsheet_to_csv(path, tmpdir)
  begin
    xlsx = Roo::Spreadsheet.open(path)
    fpath = File.join(tmpdir, File.basename(path) + SecureRandom.hex + '.csv')
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
    system(command)
    logger.info("Finishing: #{command}")
    yield if block_given?
  end
end

def JSONize(files, tmpdir, logger)
  threads = files.map do |f|
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

  def close
    @targets.each(&:close)
  end
end

# main class App
class App < Sinatra::Base
  configure do
    set :server, :puma
  end

  configure :test do
  end

  get '/' do
    erb :form
  end

  post '/convert' do
    logfile = Tempfile.create(['log', '.txt']).path
    puts "Running #{settings.environment}, logging in #{logfile}"
    logger = if settings.environment == :test
               logger = Logger.new(MultiIO.new(STDERR, File.open(logfile, 'a')))
               logger.level = Logger::DEBUG
               logger
             elsif settings.environment == :test
               logger = Logger.new(logfile)
               logger.level = Logger::DEBUG
               logger
             else
               logger = Logger.new(logfile)
               logger.level = Logger::INFO
               logger
             end

    files = request.env['rack.tempfiles']
    zip = Tempfile.create(['converted', '.zip']).path
    logger.info("Reading #{files.inspect}")
    Dir.mktmpdir do |tmpdir|
      Zip::File.open(zip, Zip::File::CREATE) do |zipfile|
        index = {}
        JSONize(files, tmpdir, logger).each do |path|
          logger.info("Adding #{path}")
          zipfile.add(File.basename(path), path)
          zipfile.commit()
          get_link_and_label(path) do |link, label|
            index[link] ||= []
            index[link] << {
              'file' => File.basename(path),
              'label' => label,
              'format' => 'application/ld+json'
            }
          end
        end
        Tempfile.create('tmp') do |f|
          f.puts index.to_json
          f.flush
          zipfile.add('index.json', f)
          zipfile.add('log.txt', logfile)
          zipfile.commit
          send_file(zip, filename: File.basename(zip))
        end
      end
    end
  end

  get '/env' do
    ENV.inspect
  end
end
