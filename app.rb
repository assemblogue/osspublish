require 'sinatra'
require "sinatra/reloader" if development?
require 'zip'
require 'tempfile'
require 'thwait'
require 'logger'

configure { set :server, :puma }

def convert(files, tmpdir, logger)
  ofiles = []
  threads = []
  
  files.each do |f|
    base = File.basename(f, suffix='.csv')
    ofiles << "#{tmpdir}/#{base}"
    threads << Thread.new do
      logger.info("Starting #{f.path}")
      logger.info("cat #{f.path} | perl plrv2/contentsdata/cto/cto.pl #{tmpdir}/#{base} #{base}")
      system("cat #{f.path} | perl plrv2/contentsdata/cto/cto.pl #{tmpdir}/#{base} ''")
      logger.info("Finishing #{f.path}")
    end
    
    threads << Thread.new do
      logger.info("Starting #{f.path}")
      system("cat #{f.path} | perl plrv2/contentsdata/cto/cts.pl #{tmpdir}/#{base} ''")
      logger.info("Finishing #{f.path}")
    end
  end
  ThreadsWait.all_waits(*threads)
  
  Dir.glob("#{tmpdir}/*.jsonld").each do |f|
    yield f
  end
end

get '/' do
  erb :form
end

post '/convert' do
  logfile = Tempfile.create(['log', '.txt']).path
  puts "Logging in #{logfile}"
  logger = Logger.new(logfile)
  logger.level = Logger::INFO

  files = request.env['rack.tempfiles']
  zip = Tempfile.create(['convert', '.zip']).path
  logger.info("Reading #{files.inspect}")
  Dir.mktmpdir do |tmpdir|
    Zip::File.open(zip, Zip::File::CREATE) do |zipfile|
      tmpdir = '/tmp/my'
      convert(files, tmpdir, logger) do |x|
        logger.info("Adding #{x}")
        zipfile.add(File.basename(x), x)
        zipfile.commit()
      end
      zipfile.add('log.txt', logfile)
      zipfile.commit()
      send_file(zip, {:filename => File.basename(zip)})
    end
  end
end

get '/env' do
  ENV.inspect
end
