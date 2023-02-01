FROM ruby:3.0.5 AS base
WORKDIR /usr/src/myapp
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
COPY Gemfile Gemfile.lock ./
RUN bundle config build.nokogiri --use-system-libraries
RUN bundle install
RUN curl -L https://cpanmin.us | perl - App::cpanminus
RUN cpanm --notest Text::CSV_XS JSON
COPY . /usr/src/myapp

FROM base AS test
RUN cpanm --notest Text::CSV_XS JSON::Parse
CMD ./run_server_tests.sh

FROM base AS prod
CMD bundle exec rackup -p ${PORT:-9292} -E ${RACK_ENV:-test}
