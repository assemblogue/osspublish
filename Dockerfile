FROM ruby:2.7
COPY . /usr/src/myapp
WORKDIR /usr/src/myapp
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
RUN bundle config build.nokogiri --use-system-libraries
RUN bundle install
RUN curl -L https://cpanmin.us | perl - App::cpanminus
RUN cpanm --notest Text::CSV_XS JSON
CMD bundle exec rackup -p $PORT -E ${RACK_ENV:-test}
