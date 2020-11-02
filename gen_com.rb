# coding: utf-8

require 'json'
require 'digest'

# 引数としてオントロジーやスタイルシートのJSON-LDファイルをわたすと、
# それを自分のアカウントにアップロードするための
# plr コマンド列を出力するスクリプトです。
# アカウント名は plr@assemblogue.com を想定しています（必要に応じて書き換えてください）。

# 新規アップロードのみをサポートしています

# add methods to Hash
class Hash
  # return self[list[0]] || self[list[1] || ....
  def lookup_by_any_key(list)
    list.each do |x|
      if key?(x)
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
    '_stylesheet_groupsummary' => 'channelSS',
    '_stylesheet_chronologicalsummary' => 'chronologicalSS',
    '_stylesheet_singlechannelsummary' => 'singleChannelSS',
    '_stylesheet_questionnaire' => 'questionnaire',
    '_stylesheet_timeline' => 'timelineSS'
  }

  link = 'ontology'
  suffix = path[/(_stylesheet_[^\d]*)\d*.jsonld$/, 1]
  link = map[suffix] if suffix

  lab = nil
  base = nil
  File.open(path) do |f|
    json = JSON.parse(f.read)
    json.lookup_by_any_key(['@id']) do |v|
      base = v
    end
    json.each_pair do |_, v|
      if v.is_a?(Hash) && v.key?('label') && v.key?('@id')
        lab ||= v['label']
        base ||= v['@id']
        break
      end
    end
    json.lookup_by_any_key(%w[summary questionnaire]) do |v|
      v.lookup_by_any_key(%w[channel unit single questionnaire]) do |w|
        if w.is_a?(Hash)
          lab ||= w['label']
          base ||= w['@id']
        end
      end
    end
    if !lab && json.key?('label')
      lab = json['label']
    end
  end

  ## TODO capture ['summary']['channel']['label'] questionnaire.questionnaire.label

  if !link || !lab || !base
    warn 'ERROR - SKIPPED ' + [path, link, lab].inspect
    return
  end
  yield link, lab, base
end

def my_basename(path)
  f = File.basename(path)
  base = f[%r{([^\/]+?)(_stylesheet_.*|).jsonld$}, 1]
  base
end

if $PROGRAM_NAME == __FILE__
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
        lang = '*' if lang == ''
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
end
