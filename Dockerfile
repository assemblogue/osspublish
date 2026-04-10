FROM docker.io/ruby:3.2.7 AS base
WORKDIR /usr/src/myapp
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
COPY Gemfile Gemfile.lock ./
RUN bundle config build.nokogiri --use-system-libraries
RUN bundle install
ENV PERL5LIB=/opt/perl5/lib/perl5
RUN curl -L https://cpanmin.us | perl - App::cpanminus
RUN cpanm --notest -L /opt/perl5 Text::CSV_XS JSON
COPY . /usr/src/myapp

FROM base AS test
RUN cpanm --notest -L /opt/perl5 JSON::Parse
CMD ./run_server_tests.sh

FROM docker.io/ruby:3.2.7-slim AS prod
ENV PERL5LIB=/opt/perl5/lib/perl5
WORKDIR /app
COPY --from=base /usr/local/bundle /usr/local/bundle
COPY --from=base /usr/lib/x86_64-linux-gnu/perl /usr/lib/x86_64-linux-gnu/perl
COPY --from=base /opt/perl5 /opt/perl5
COPY . .
CMD bundle exec puma -e ${RACK_ENV:-test}
