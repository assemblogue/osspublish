FROM ruby:2.7
COPY . /usr/src/myapp
WORKDIR /usr/src/myapp
RUN curl -L http://cpanmin.us | perl - App::cpanminus
RUN cpanm --notest Text::CSV_XS JSON Encode
RUN bundle config build.nokogiri --use-system-libraries
RUN bundle install
ENV PORT=${PORT}
CMD ["bundle", "exec", "rackup", "-E", "production"]
