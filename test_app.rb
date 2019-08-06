# coding: utf-8

ENV['APP_ENV'] = 'test'

require './app'
require 'test/unit'
require 'rack/test'
require 'json'

# Unit tests for class App
class AppTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    App
  end

  def test_it_contains_submit_button
    get '/'
    assert last_response.ok?
    assert last_response.body.include? '<button>Submit</button>'
  end

  def unzip(str)
    unzipped = {}
    Zip::InputStream.open(StringIO.new(str)) do |io|
      while (entry = io.get_next_entry)
        unzipped[entry.name] = io.read
      end
    end
    unzipped
  end

  def post_for_csv(content)
    Tempfile.create(['tmp', '.csv']) do |f|
      f.puts content
      f.flush

      post '/convert',
           params: { 'file': Rack::Test::UploadedFile.new(f.path, 'text/csv') }
      assert last_response.ok?
      unzip(last_response.body)
    end
  end
  
  def test_it_gives_zipped_log
    unzipped = post_for_csv('foo,bar')
    assert_includes unzipped.keys, 'log.txt'
    assert_includes unzipped.keys, 'index.json'
  end

  def test_it_gives_zipped_jsonld
    unzipped = post_for_csv <<EOD
"]O Base ja:基本!;Base!",
"Event ja:事象;Event","begin=1 ja:開始;begin","dateTime"
EOD

    index = JSON.parse(unzipped['index.json'])
    assert_equal index['ontology'][0]['label']['ja'], '基本!'
    assert_equal index['ontology'][0]['label'][''], 'Base!'
  end
  
  def test_it_gives_stylesheet
    unzipped = post_for_csv <<EOD
"]O Base Base",
"Event ja:事象;Event",
"]G LivingTest S d
en:Living Test"
EOD

    index = JSON.parse(unzipped['index.json'])
    assert_equal index['channelSS'][0]['label']['en'], 'Living Test'
  end
end
