require './app'
# unless ENV['PORT']
#   warn 'PORT is not set'
#   Rack::Handler.default.run(App)
# else
#   Rack::Handler.default.run(App, Port: ENV['PORT'])
# end

run App
