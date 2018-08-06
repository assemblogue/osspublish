# coding: utf-8
require 'json'
require 'digest'

# 引数としてオントロジーやスタイルシートのJSON-LDファイルをわたすと、
# それを自分のアカウントにアップロードするための
# plr コマンド列を出力するスクリプトです。
# アカウント名は plr@assemblogue.com を想定しています（必要に応じて書き換えてください）。

# 新規アップロードのみをサポートしています

class Hash
  def lookup_by_any_key(ls)
    ls.each do |x|
      if self.has_key?(x)
        yield self[x]
        break
      end
    end
  end
end

def get_link_and_label(path)
  map = {
    '_stylesheet_restriction' => 'restriction',
    '_stylesheet_constraint' => 'constraint',
    '_stylesheet_unitsummary' => 'unitTimeSS',
    '_stylesheet_channelsummary' => 'channelSS',
    '_stylesheet_chronologicalsummary' => 'chronologicalSS',
    '_stylesheet_questionnaire' => 'questionnaire',
    '_stylesheet_timeline' => 'timelineSS',
  }

  link = 'ontology'
  suffix = path[/(_stylesheet_[^\d]*)\d*.jsonld$/, 1]
  if suffix then
    link = map[suffix]
  end

  lab = nil
  open(path) do |f|
    json = JSON.load(f)
    json.each_pair do |k,v|
      if v.is_a?(Hash) and v.has_key?('label')
        lab = v['label']
        break
      end
    end
    json.lookup_by_any_key(['summary', 'questionnaire']) do |v|
      v.lookup_by_any_key(['channel', 'unit', 'questionnaire']) do |w|
        if w.is_a?(Hash) then
          lab = w['label']
        end
      end
    end
    if not lab and json.has_key?('label') then
      lab = json['label']
    end
  end

  ## TODO ['summary']['channel']['label'] questionnaire.questionnaire.label を認識

  if not link or not lab then
    STDERR.puts 'ERROR - SKIPPED ' + [path, link, lab].inspect
    return
  end
  yield link, lab
end

def my_basename(path)
  f = File::basename(path)
  base = f[/([^\/]+?)(_stylesheet_.*|).jsonld$/, 1]
  base
end

account = 'plr@assemblogue.com'
puts ''
puts 'new oss inner OSS'
puts 'o 0'
puts ''
i = 0
ARGV.each do |path|
  get_link_and_label(path) do |link, label|
    puts "new #{link} file #{path}"
    puts ''
    label.each_pair do |lang, title|
      if lang == '' then
        lang = '*'
      end
      puts "#{i} title #{lang} #{title}"
    end
    puts "#{i} format application/ld+json"
    puts "#{i} peer"
    base = my_basename(path)
    key = [link, label.to_a].inspect
    puts "new ossId literal * #{account}##{Digest::SHA256.hexdigest(key)[0..15]}##{base}_#{link}"
    puts 'b'
    puts 'l'
    puts ''
    i += 1
  end
end
