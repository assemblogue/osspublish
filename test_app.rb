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

  def test_it_gives_zipped_log
    Tempfile.create(['tmp', '.csv']) do |f|
      f.puts 'foo,bar'
      f.flush

      post '/convert', params: { 'file': Rack::Test::UploadedFile.new(f.path, 'text/csv') }
      assert last_response.ok?
      unzipped = unzip(last_response.body)
      assert unzipped.key? 'log.txt'
    end
  end

  def test_it_gives_zipped_jsonld
    Tempfile.create(['tmp', '.csv']) do |f|
      f.puts <<EOD
"]O Base ja:基本!;Base!",
"Event ja:事象;Event","begin=1 ja:開始;begin","dateTime"
EOD
      f.flush
      post '/convert', params: { 'file': Rack::Test::UploadedFile.new(f.path, 'text/csv') }
      assert last_response.ok?
      unzipped = unzip(last_response.body)
      index = JSON.parse(unzipped['index.json'])
      assert_equal index['ontology'][0]['label']['ja'], '基本!'
      assert_equal index['ontology'][0]['label'][''], 'Base!'
    end
  end

end
