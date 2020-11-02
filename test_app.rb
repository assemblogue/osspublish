# coding: utf-8

ENV['APP_ENV'] = 'test'

require './app'
require 'test/unit'
require 'rack/test'
require 'json'

def unzip(str)
  unzipped = {}
  Zip::InputStream.open(StringIO.new(str)) do |io|
    while (entry = io.get_next_entry)
      unzipped[entry.name] = io.read
    end
  end
  unzipped
end

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
    unzipped = post_for_csv(
      <<~CSV
        "]O Base ja:基本!;Base!",
        "Event ja:事象;Event","begin=1 ja:開始;begin","dateTime"
      CSV
    )

    index = JSON.parse(unzipped['index.json'])
    assert_equal ['ontology'], index.keys
    assert_equal '基本!', index['ontology'][0]['label']['ja']
    assert_equal 'Base!', index['ontology'][0]['label']['']
    assert_equal 'Base', index['ontology'][0]['id']
  end

  def test_it_gives_log
    unzipped = post_for_csv('')
    assert_equal [], JSON.parse(unzipped['index.json']).keys
    assert_not_equal '', unzipped['log.txt']
  end

  def test_it_gives_stylesheet
    unzipped = post_for_csv(
      <<~CSV
        "]O Base Base",
        "Event ja:事象;Event",
        "]G LivingTest S d
        en:Living Test"
      CSV
    )

    index = JSON.parse(unzipped['index.json'])

    assert_equal 'Living Test', index['channelSS'][0]['label']['en']
  end

  def test_empty_ontology_nonempty_stylesheet_single
    unzipped = post_for_csv(
      <<~CSV
        "]S TempearturePlate ja:温度板;Temperature Plate 14d",
        "n","","b|[]|H14dd"
        "L blue|ja:体温;Body Temperature","","G|[%BodyTemperature%bodyTempVal]"
      CSV
    )

    index = JSON.parse(unzipped['index.json'])

    assert_equal ['singleChannelSS'], index.keys
    assert_equal 'Temperature Plate', index['singleChannelSS'][0]['label']['']
  end

  def test_parse_ontology_link_label
    Tempfile.create(['tmp', '.jsonld']) do |f|
      f.puts <<~JSON
        {
           "@context" : "http://PUBLIC/ontologies/menuContext.jsonld",
           "@id" : "BaseOntology",
           "@type" : "PlrOntology",
           "defines" : [
              {
                 "@id" : "#_none",
                 "@type" : "Class",
                 "comment" : {
                    "" : "autonomous",
                    "ja" : "自立"
                 },
                 "label" : {
                    "" : "none",
                    "ja" : "無"
                 }
              }],
           "label" : {
              "" : "Base",
              "ja" : "基本!"
           }
        }
      JSON
      f.flush

      assert_equal ['ontology', { '' => 'Base', 'ja' => '基本!' }, 'BaseOntology'],
                   get_link_and_label(f.path) { |link, labels, base| [link, labels, base] }
    end
  end

  def test_parse_restriction
    Tempfile.create(['x', '_stylesheet_restriction.jsonld']) do |f|
      f.puts <<~JSON
        {
           "@context" : "http://PUBLIC/ontologies/menuContext.jsonld",
           "restriction" : {
              "@id" : "DisclosureRequest",
              "defines" : [
                 {
                    "#reply" : "h"
                 },
                 {
                    "#DisclosureConsent" : "h"
                 }
              ],
              "label" : {
                 "" : "Disclosure Request",
                 "ja" : "開示要請"
              }
           }
        }
      JSON
      f.flush

      assert_equal ['restriction', { '' => 'Disclosure Request', 'ja' => '開示要請' }, 'DisclosureRequest'],
                   get_link_and_label(f.path) { |link, labels, base| [link, labels, base] }
    end
  end
end
