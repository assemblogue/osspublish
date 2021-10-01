#! /bin/sh
# For running these tests
# - See Dockerfile and install dependencies locally
# - Have Java 8 environment
ruby test_app.rb && ./gradlew test
