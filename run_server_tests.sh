#! /bin/bash

env APP_ENV=test ruby test_app.rb && pushd plrv2/contentsdata/cto && perl tests.pl
