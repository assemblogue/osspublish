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
    unzipped = post_for_csv <<EOD
"]O Base ja:基本!;Base!",
"Event ja:事象;Event","begin=1 ja:開始;begin","dateTime"
EOD

    index = JSON.parse(unzipped['index.json'])
    assert_equal index['ontology'][0]['label']['ja'], '基本!'
    assert_equal index['ontology'][0]['label'][''], 'Base!'
    assert_equal index['ontology'][0]['id'], 'Base'
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

  def test_parse_ontology
    Tempfile.create(['tmp', '.jsonld']) do |f|
      f.puts <<EOD
{
   "@context" : "http://PUBLIC/ontologies/menuContext.jsonld",
   "@id" : "BaseOntology",
   "@type" : "Ontology",
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
EOD
      f.flush

      assert_equal ['ontology',  {""=>"Base", "ja"=>"基本!"}, 'BaseOntology'], get_link_and_label(f.path) {|link,labels,base| [link,labels,base]}
    end
  end
  
  def test_parse_restriction
    Tempfile.create(['x', '_stylesheet_restriction.jsonld']) do |f|
      f.puts <<EOD
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
EOD
      f.flush

      assert_equal ['restriction',  {""=>"Disclosure Request", "ja"=>"開示要請"}, 'DisclosureRequest'], get_link_and_label(f.path) {|link,labels,base| [link,labels,base]}
    end
  end
end
