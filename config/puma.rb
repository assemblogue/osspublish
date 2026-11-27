workers 0
threads 1, 2
bind "tcp://[::]:#{ENV.fetch('PORT','9292')}"
preload_app!
http_content_length_limit 5_000_000
