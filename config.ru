require './app'
if not ENV['PORT'] then
  STDERR.puts 'PORT is not set'
  exit 1
else
  Rack::Handler.default.run(App, :Port => ENV['PORT'])
end
