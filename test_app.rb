# frozen_string_literal: true

require './app'
require 'test/unit'
require 'rack/test'
require 'net/http/post/multipart'
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

HOST = URI.parse('https://osspublish.fly.dev')

class SimpleResponse
  attr_accessor :success, :body

  def initialize(success, body)
    self.success = success
    self.body = body
  end

  def ok?
    success
  end
end

# Unit tests for class App
class AppTest < Test::Unit::TestCase
  if ENV['APP_ENV'] == 'production'
    require 'open-uri'
    require 'net/http'
    AppTest.attr_accessor(:last_response)
    def get(path)
      uri = HOST.clone
      uri.path = path
      res = uri.open
      puts("GET: #{res.inspect}")
      self.last_response = SimpleResponse.new(res.status[0] == '200', res.read)
    end

    def post(path, params = {})
      uri = HOST.clone
      uri.path = path
      req = Net::HTTP::Post::Multipart.new(uri, params)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.set_debug_output($stderr)
      res = http.request(req)
      self.last_response = SimpleResponse.new(res.is_a?(Net::HTTPSuccess),
                                              res.body)
    end
  else
    include Rack::Test::Methods
  end

  def app
    App
  end

  def test_it_contains_submit_button
    get '/'
    assert_true last_response.ok?
    assert_include last_response.body, '<button>Submit</button>'
  end

  def post_for_csv(content)
    Tempfile.create(['tmp', '.csv']) do |f|
      f.puts content
      f.flush

      post '/convert',
           'file' => Rack::Test::UploadedFile.new(f.path, 'text/csv')
      assert last_response.ok?
      unzip(last_response.body)
    end
  end

  def test_it_gives_zipped_log
    unzipped = post_for_csv('foo,bar')
    assert_include unzipped.keys, 'log.txt'
    assert_include unzipped.keys, 'index.json'
  end

  def test_it_rejects_request_without_files
    omit_if(ENV['APP_ENV'] == 'production', 'rack-test only')

    post '/convert'

    assert_equal 400, last_response.status
    assert_match %r{\Aapplication/json}, last_response.content_type
    assert_equal({ 'error' => 'No files uploaded' }, JSON.parse(last_response.body))
  end

  def test_it_converts_multiple_files
    omit_if(ENV['APP_ENV'] == 'production', 'rack-test only')

    csvs = ["\"]O Base Base\",\n\"Event Event\"\n", "\"]O Other Other\",\n\"Thing Thing\"\n"]
    tempfiles = csvs.map do |content|
      Tempfile.create(['tmp', '.csv']).tap do |f|
        f.puts content
        f.flush
      end
    end

    begin
      uploads = tempfiles.map { |f| Rack::Test::UploadedFile.new(f.path, 'text/csv') }
      post '/convert', 'file[]' => uploads
      assert last_response.ok?
    ensure
      tempfiles.each do |f|
        f.close
        File.unlink(f.path)
      end
    end

    unzipped = unzip(last_response.body)
    index = JSON.parse(unzipped['index.json'])

    assert_equal 2, index['response'].length
    assert_equal [[], []], index['response'].map { |r| r['error'] }
    assert_equal %w[Base Other], index['ontology'].map { |e| e['id'] }.sort
    index['ontology'].each { |e| assert_include unzipped.keys, e['file'] }
  end

  # Posts several files at once. Each item is { content:, ext: '.csv', name: nil }.
  # Returns the unzipped response.
  def post_uploads(items)
    tempfiles = items.map do |item|
      Tempfile.create(['tmp', item.fetch(:ext, '.csv')]).tap do |f|
        f.binmode
        f.write(item[:content])
        f.flush
      end
    end

    begin
      uploads = tempfiles.zip(items).map do |f, item|
        Rack::Test::UploadedFile.new(f.path, 'text/csv', original_filename: item[:name])
      end
      post '/convert', 'file[]' => uploads
      assert last_response.ok?
    ensure
      tempfiles.each do |f|
        f.close
        File.unlink(f.path)
      end
    end

    unzip(last_response.body)
  end

  def test_it_keeps_converting_when_one_file_fails
    omit_if(ENV['APP_ENV'] == 'production', 'rack-test only')

    unzipped = post_uploads(
      [
        { content: "\"]O Bad Bad\",\n\"Event Event\",\n,\"| missingProperty\",\"value\"\n", name: 'bad.csv' },
        { content: "\"]O Good Good\",\n\"Event Event\"\n", name: 'good.csv' }
      ]
    )
    index = JSON.parse(unzipped['index.json'])
    errors = index['response'].to_h { |r| [r['file'], r['error']] }

    assert_equal %w[bad.csv good.csv], errors.keys.sort
    assert_not_empty errors['bad.csv']
    assert_equal [], errors['good.csv']
    # all-or-nothing: nothing from the failed input is included
    assert_equal ['Good'], index['ontology'].map { |e| e['id'] }
    index['ontology'].each { |e| assert_include unzipped.keys, e['file'] }
  end

  def test_it_keeps_converting_when_a_spreadsheet_is_corrupt
    omit_if(ENV['APP_ENV'] == 'production', 'rack-test only')

    unzipped = post_uploads(
      [
        { content: 'this is not a spreadsheet', ext: '.xlsx', name: 'broken.xlsx' },
        { content: "\"]O Good Good\",\n\"Event Event\"\n", name: 'good.csv' }
      ]
    )
    index = JSON.parse(unzipped['index.json'])
    errors = index['response'].to_h { |r| [r['file'], r['error']] }

    assert_not_empty errors['broken.xlsx']
    assert_not_nil errors['broken.xlsx'][0]['message']
    assert_equal [], errors['good.csv']
    assert_equal ['Good'], index['ontology'].map { |e| e['id'] }
  end

  def test_it_converts_files_with_the_same_name
    omit_if(ENV['APP_ENV'] == 'production', 'rack-test only')

    unzipped = post_uploads(
      [
        { content: "\"]O First First\",\n\"Event Event\"\n", name: 'dup.csv' },
        { content: "\"]O Second Second\",\n\"Event Event\"\n", name: 'dup.csv' }
      ]
    )
    index = JSON.parse(unzipped['index.json'])

    assert_equal [{ 'file' => 'dup.csv', 'error' => [] }] * 2, index['response']
    assert_equal %w[First Second], index['ontology'].map { |e| e['id'] }.sort
    assert_equal 2, index['ontology'].map { |e| e['file'] }.uniq.length
    index['ontology'].each { |e| assert_include unzipped.keys, e['file'] }
  end

  def test_it_gives_ontology
    unzipped = post_for_csv(
      <<~CSV
        "]O Base ja:基本!;Base!",
        "Event ja:事象;Event","begin=1 ja:開始;begin","dateTime"
      CSV
    )

    index = JSON.parse(unzipped['index.json'])
    assert_equal %w[ontology response], index.keys.sort
    assert_equal [], index['response'][0]['error']
    assert_equal '基本!', index['ontology'][0]['label']['ja']
    assert_equal 'Base!', index['ontology'][0]['label']['']
    assert_equal 'Base', index['ontology'][0]['id']
  end

  def test_it_gives_ontology_content
    unzipped = post_for_csv(
      <<~CSV
        "]O Base ja:基本!;Base!",
        "Event(1 ja:事象;Event","begin=1 ja:開始;begin","dateTime"
      CSV
    )

    index = JSON.parse(unzipped['index.json'])
    assert_equal %w[ontology response], index.keys.sort
    ontology = JSON.parse(unzipped[index['ontology'][0]['file']])
    result = ontology['defines'].find { |x| x['@id'] == '#Event' }.keys.sort
    assert_equal ['@id', '@type', 'label', 'maxClassCardinality', 'subClassOf'], result
  end

  def test_it_gives_log
    unzipped = post_for_csv('')
    assert_equal ['response'], JSON.parse(unzipped['index.json']).keys
    assert_not_equal '', unzipped['log.txt']
  end

  def test_it_includes_empty_error_response_for_successful_conversion
    unzipped = post_for_csv(
      <<~CSV
        "]O Base Base",
        "Event Event"
      CSV
    )

    response = JSON.parse(unzipped['index.json'])['response']
    assert_equal 1, response.length
    assert_equal [], response[0]['error']
  end

  def test_it_includes_error_response_for_failed_conversion
    unzipped = post_for_csv(
      <<~CSV
        "]O Base Base",
        "Event Event",
        ,"| missingProperty","value"
      CSV
    )

    response = JSON.parse(unzipped['index.json'])['response']
    assert_equal 1, response.length
    assert_not_empty response[0]['error']

    error = response[0]['error'].find do |entry|
      entry['command'].to_s.include?('cto.pl')
    end

    assert_not_nil error
    assert_include error['message'], "Error: undefined property `missingProperty'"
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

    assert_equal %w[response singleChannelSS], index.keys.sort
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
