#! /bin/sh
# For running these tests
# - See Dockerfile and install dependencies locally
# - Have Java 8 environment
APP_ENV=test ruby test_app.rb && ./gradlew test
