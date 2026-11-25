#! /usr/bin/perl
use strict;
use IPC::Open2;
use POSIX ':sys_wait_h';
use File::Temp qw/tempdir/;
use JSON::Parse 'json_file_to_perl';
use Test::More tests => 64;

sub run_command {
	my $command = shift;
	my $content = shift;
	my $dir = shift;
	my $prefix = shift;
	# 残りの引数はそのまま渡す（使い方の誤りの試験）。エラーの文は $dir/$prefix.err に残す
	my $pid = open2(my $child_in, my $child_out, join(' ', "$^X ./$command $dir/$prefix $prefix", @_, "2>$dir/$prefix.err")) or die "$!";
	print $child_out $content;
	close $child_in;
	close $child_out;
	waitpid $pid, 0;
	return $dir;
}

my $dir = tempdir('/tmp/plrtest_XXXX');

{
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_hyphen');
	"]O Family
	ja:家族;Family",\オントロジー,,,
	"Nuclear-Family
	ja:核家族;nuclear family",child ja:子;child,Person,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_hyphen.jsonld");
	my $val = [$p->{'defines'}->[0]->{'@id'}, $p->{'defines'}->[1]->{'@id'}];
	is_deeply([sort @$val],
						[sort ('#child', '#Nuclear-Family')],
						'class name with hyphen');
}

{
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_abbrev1');
	"]O Family ja:家族;Family",\オントロジー,,,
	"Nuclear-Family ja:核家族;nuclear family|NF|"
	EOD
	my $p = json_file_to_perl("$dir/plrTest_abbrev1.jsonld");
	my $val = $p->{'defines'}->[0]->{'abbrev'};
	is_deeply($val,
						{'' => 'NF'},
						'abbrev');
}

{
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_abbrev2');
	"]O Family ja:家族;Family",\オントロジー,,,
	"Nuclear-Family ja:核家族;nuclear family|%|"
	EOD
	my $p = json_file_to_perl("$dir/plrTest_abbrev2.jsonld");
	my $val = $p->{'defines'}->[0]->{'abbrev'};
	is_deeply($val,
						{'' => ''},
						'empty abbrev');
}

{
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_reserved');
	"]O Family ja:家族;Family",\オントロジー,,,
	"Nuclear-Family ja:核家族;nuclear family",child,PlrId,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_reserved.jsonld");
	my $val = $p->{'defines'}->[1];
	is_deeply($val, {
		'domain' => '#Nuclear-Family',
		'@type' => 'ObjectProperty',
		'range' => 'PlrId',
		'@id' => '#child'
	}, 'reserved class');
}

{
	# "| 属性" の右隣のカラムは、直近のクラスのその属性の値
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_classvalue');
	"]O Calc ja:計算;Calc",\オントロジー,,,
	Atom,builtInFunction(1,string,,
	,compensatesWith=1,Atom,,
	Constraint,,,,
	,Equal =,| builtInFunction,Equal,
	,Undo,,,
	,Order,| compensatesWith,Undo,
	,,,Other,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_classvalue.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	# 鍵は # 付きの属性 ID（読む側でオントロジーの ID が前に付かないように）
	is($d{'#Equal'}->{'#builtInFunction'}, 'Equal', 'class property value (string)');
	ok(!exists($d{'#Equal'}->{'builtInFunction'}), 'class property value has no bare key');
	# ObjectProperty の値は ID。前の行から引き継いだ "| 属性" は値を書き直さない
	is_deeply($d{'#Order'}->{'#compensatesWith'}, {'@id' => '#Undo'},
						'class property value (object), not overwritten by carried column');
}

{
	# 属性の定義が値より後の行にあっても、ObjectProperty なら ID にする
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_classvalue_later');
	"]O Calc ja:計算;Calc",\オントロジー,,,
	Constraint,,,,
	,Order,| compensatesWith,Undo,
	,Undo,,,
	Atom,compensatesWith=1,Atom,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_classvalue_later.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply($d{'#Order'}->{'#compensatesWith'}, {'@id' => '#Undo'},
						'class property value (object), property defined later');
}

{
	# 値域が数なら数で書く（"0" も値）
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_classvalue_number');
	"]O Calc ja:計算;Calc",\オントロジー,,,
	Atom,count(1,integer,,
	Constraint,,,,
	,Zero,| count,0,
	EOD
	open(my $f, '<', "$dir/plrTest_classvalue_number.jsonld") or die "$!";
	my $text = do { local $/; <$f> };
	like($text, qr/"#count"\s*:\s*0\b/, 'class property value "0" as a number');
}

{
	# 前の行から引き継いだ値のカラムは、属性やクラスとして読み直さない
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_classvalue_carried');
	"]O Calc ja:計算;Calc",\オントロジー,,,,
	Atom,builtInFunction(1,string,,,
	Constraint,,,,,
	,Equal =,| builtInFunction,equal,,
	,,,,Deeper,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_classvalue_carried.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	ok(!exists($d{'#equal'}), 'carried value column is not read as a property');
}

{
	# 系の予約属性は、シートに宣言が無くても文字列として書く（宣言は系の側にある）
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_reserved_property');
	"]O Calc ja:計算;Calc",\オントロジー,,,
	Constraint,,,,
	,Equal =,| builtInFunction,equal,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_reserved_property.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is($d{'#Equal'}->{'#builtInFunction'}, 'equal',
		 'reserved property value without declaration');
	ok(!exists($d{'#builtInFunction'}), 'reserved property is not declared');
}

{
	# 系の予約属性 linkPath（plrDart の追記R971・R972）：arg1 から arg2 へたどる属性の
	# ID を空白で区切って並べ、逆向きの属性には - を付ける。JSON-LD では歩みの @list に
	# し、歩みは SHACL の属性の道の形（順向きは # 付きの ID、逆向きは inversePath で
	# 包む）にする。道の属性に表の中のラベルの定義が無ければ（系の属性 truthValue など）、
	# ラベルの無い属性として知らせ、変換は続ける
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_link_path');
	"]O DG ja:議論;DG",\オントロジー,,,
	Issue,conjSubIssue ja:連言の下位;conj sub,Issue,,
	Answer,isTrue ja:真か;is true,boolean,,
	GraphRelation,,,,
	,ConjSubIssue,| linkPath,conjSubIssue,
	,Then,| linkPath,truthValue -isTrue,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_link_path.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply($d{'#ConjSubIssue'}->{'#linkPath'},
						{'@list' => [{'@id' => '#conjSubIssue'}]},
						'linkPath of one step');
	# truthValue は系の属性、isTrue はシートの属性
	is_deeply($d{'#Then'}->{'#linkPath'},
						{'@list' => [{'@id' => '#truthValue'},
												 {'inversePath' => {'@id' => '#isTrue'}}]},
						'linkPath of two steps with an inverse one');
	ok(!exists($d{'#linkPath'}), 'linkPath is not declared');
	my $err = errorText('plrTest_link_path');
	like($err, qr/Warning: property `truthValue' .*has no label/, 'linkPath: a property without a label is warned');
	unlike($err, qr/`(conjSubIssue|isTrue)' .*has no label/, 'linkPath: properties labelled in the sheet are not warned');
}

# linkPath の道の属性の所に、表でクラスとして定義した名前を書くとエラー（出力を作らない）
foreach my $case (
	['plrTest_link_path_class', ",Cls,| linkPath,Issue,\n", 'class in linkPath'],
) {
	my ($prefix, $row, $name) = @$case;
	run_command('cto.pl',
		"\"]O DG ja:議論;DG\",\\オントロジー,,,\nIssue,conjSubIssue,Issue,,\nGraphRelation,,,,\n$row",
		$dir, $prefix);
	ok($? != 0 && !-e "$dir/$prefix.jsonld", "error: $name");
}

# linkPath の道に、表に定義の無い属性（書き誤り）を書くと、知らせて変換は続ける
run_command('cto.pl',
	"\"]O DG ja:議論;DG\",\\オントロジー,,,\nIssue,conjSubIssue ja:連言の下位;conj sub,Issue,,\nGraphRelation,,,,\n,Typo,| linkPath,conjSubIsue,\n",
	$dir, 'plrTest_link_path_typo');
ok($? == 0 && -e "$dir/plrTest_link_path_typo.jsonld", 'linkPath: an undefined property does not stop the conversion');
# 表に無い名前は、大文字で始まっても（系のクラス Constraint など）、綴りでは見分けず、ラベルの無い属性として
# 知らせて変換は続ける
run_command('cto.pl',
	"\"]O DG ja:議論;DG\",\\オントロジー,,,\nIssue,conjSubIssue ja:連言の下位;conj sub,Issue,,\nGraphRelation,,,,\n,SysCls,| linkPath,Constraint,\n",
	$dir, 'plrTest_link_path_sysclass');
ok($? == 0 && -e "$dir/plrTest_link_path_sysclass.jsonld", 'linkPath: a name not in the sheet does not stop the conversion even if it starts with a capital');
like(errorText('plrTest_link_path_sysclass'), qr/Warning: property `Constraint' .*has no label/, 'warning text: a name not in the sheet in linkPath');

# エラーの文が、どこを直せばよいかを言う
sub errorText {
	my ($prefix) = @_;
	open(my $f, '<:encoding(UTF-8)', "$dir/$prefix.err") or return '';
	local $/;
	return <$f>;
}
# - だけの歩みは「- の後に属性が無い」
run_command('cto.pl',
	"\"]O DG ja:議論;DG\",\\オントロジー,,,\nIssue,conjSubIssue,Issue,,\nGraphRelation,,,,\n,Dash,| linkPath,conjSubIssue -,\n",
	$dir, 'plrTest_link_path_dash');
like(errorText('plrTest_link_path_dash'), qr/no property after `-'/, 'error text: "-" without a property');
like(errorText('plrTest_link_path_typo'), qr/Warning: property `conjSubIsue' .*has no label/, 'warning text: undefined property in linkPath');
like(errorText('plrTest_link_path_class'), qr/class `Issue' in `\| linkPath'/, 'error text: class in linkPath');
# ほかのオントロジーは読まない：3つ目からの引数は使い方の誤り
run_command('cto.pl', "\"]O DG ja:議論;DG\",\\オントロジー,,,\n", $dir, 'plrTest_extra_args', 'Base.jsonld');
ok($? != 0 && !-e "$dir/plrTest_extra_args.jsonld", 'error: an extra argument');

# 値の無い "| 属性" はエラー（出力を作らない）。書き違いの属性は、ラベルの無い属性として知らせる（下の試験）
foreach my $case (
	['plrTest_classvalue_empty', ",Empty,| count,,\n", 'empty value'],
	['plrTest_classvalue_last', ",Last,| count\n", '"| property" as the last column'],
) {
	my ($prefix, $row, $name) = @$case;
	run_command('cto.pl',
		"\"]O Calc ja:計算;Calc\",\\オントロジー,,,\nAtom,count(1,integer,,\nConstraint,,,,\n$row",
		$dir, $prefix);
	ok($? != 0 && !-e "$dir/$prefix.jsonld", "error: $name");
}

{
	# A 列の予約クラス名（ラベル付きでも）は組込みのクラスを指す。宣言せず、
	# 続く属性の domain にする。前の行の属性の値域の続きとして読まない（osspublish#3）
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_reserved_decl');
	"]O Family ja:家族;Family",\オントロジー,,,
	"Task ja:タスク;Task",,,
	,"notificationLeadTime ja:通知リードタイム;notification lead time",duration,,
	"Channel ja:チャネル;Channel",channelSetting,,,
	DataSetting,dataSettingNote,string,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_reserved_decl.jsonld");
	my %byId = map { ($_->{'@id'} // '') => $_ } @{$p->{'defines'}};
	is($byId{'#notificationLeadTime'}->{'range'}, 'duration', 'range of the property on the previous row is kept');
	ok(!exists($byId{'#Channel'}) && !exists($byId{'Channel'}), 'Channel in column A is not declared');
	is($byId{'#channelSetting'}->{'domain'}, 'Channel', 'property after it belongs to the built-in Channel');
	is($byId{'#dataSettingNote'}->{'domain'}, 'DataSetting', 'property after DataSetting belongs to the built-in DataSetting');
	my $c = json_file_to_perl("$dir/plrTest_reserved_declContext.jsonld");
	ok(!exists($c->{'@context'}->[1]->{'Channel'}), 'Channel is not in the context');
}

{
	# aiPrompt（系の予約属性。言語ごとの文字列：plrDart の追記d60）——"| aiPrompt" の行ごとに1つの言語。
	# tooltip と同じ形で、「ja:」と改行の後が本文、言語の無い値は「:」と改行で始まり鍵は ''。鍵は # 付き
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_aiprompt');
	"]O Shelter ja:避難所;Shelter",\オントロジー,,,
	"ShelterSupport ja:避難者支援;Shelter support",| aiPrompt,"ja:
	Ask gently, one field at a time",
	,| aiPrompt,"en:
	Ask one field at a time",
	"Plain ja:素;Plain",| aiPrompt,":
	no language",
	EOD
	my $p = json_file_to_perl("$dir/plrTest_aiprompt.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply($d{'#ShelterSupport'}->{'#aiPrompt'},
						{'ja' => 'Ask gently, one field at a time', 'en' => 'Ask one field at a time'},
						'aiPrompt: one language per row');
	is_deeply($d{'#Plain'}->{'#aiPrompt'}, {'' => 'no language'}, 'aiPrompt without language');
	ok(!exists($d{'#ShelterSupport'}->{'aiPrompt'}), 'aiPrompt has no bare key');
}

{
	# token（言語を持たない文字列：plrDart の追記d61）は予約語で、値域にそのまま書ける。ほかの XML Schema の
	# 文字列の型（normalizedString など）は、これまでどおり string で代えるよう知らせる
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_token');
	"]O Codes ja:コード;Codes",\オントロジー,,,
	"Item ja:品目;Item","code ja:コード;code",token,,
	,"note ja:注;note",normalizedString,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_token.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is($d{'#code'}->{'range'}, 'token', 'token: a reserved datatype');
	unlike(errorText('plrTest_token'), qr/`token'/, 'token: no warning');
	like(errorText('plrTest_token'), qr/`normalizedString' .*\(use string\)/, 'normalizedString: still told to use string');
}

{
	# データ型の値域を持つ属性に、続くクラスを値域として重ねようとしたら、その旨を知らせる
	# （checkReservedWord が引数を照らす。前は呼んだ所の $_ を照らし、この判定がいつも偽だった）
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_range_twice');
	"]O Shop ja:店;Shop",\オントロジー,,,
	"Item ja:品目;Item","weight ja:重さ;weight",decimal,"Unit ja:単位;Unit",
	EOD
	like(errorText('plrTest_range_twice'), qr/Property #weight is DatatypeProperty that already have a range\.$/m,
		'a class after a datatype range: told that the property already has a datatype range');
}

# "| 属性" の属性が表に無いとき（系の onto34 など。osspublish #9 の (b)、橋田さんの決め 2026-11-24）：
# ほかの名前と同じく、ラベルの無い属性として知らせて書く。値の綴りがクラスの名前の形なら ID、ほかは文字列
{
	# "| 属性" は、この行で直近のクラスか属性の宣言に書く（plrDart の追記R979——
	# 属性の集まりの種類 onto34 を属性に書く）。前の行から引き継いだ属性のカラムの
	# 後にも書ける
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_property_value');
	"]O W ja:作業場;W",\オントロジー,,,
	"Workplace ja:作業場;Workplace","rule ja:規則;rule","Rule ja:規則;Rule",,
	,"order ja:順;order",| onto34,_onto340,
	,"count(1 ja:数;count",integer,| onto34,_onto342,
	,"note ja:注;note",string,| memo,plain text,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_property_value.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply([$d{'#order'}->{'#onto34'}, $d{'#count'}->{'#onto34'}],
						[{'@id' => '#_onto340'}, {'@id' => '#_onto342'}],
						'property value on a property (same row, after the range)');
	ok(!exists($d{'#Workplace'}->{'#onto34'}) && !exists($d{'#Rule'}->{'#onto34'}),
		 'property value is not written to the class');
	is($d{'#note'}->{'#memo'}, 'plain text', 'a value not in the form of a class name is a string');
	my $err = errorText('plrTest_property_value');
	like($err, qr/Warning: property `onto34' .*has no label/, 'a property not in the sheet is warned');
	like($err, qr/Warning: class `_onto340' .*has no label/, 'a value not in the sheet is warned');
}

{
	# 前の行から引き継いだ属性のカラムの後の "| 属性" も、その属性に書く
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_property_value_carried');
	"]O W ja:作業場;W",\オントロジー,,,
	"Workplace ja:作業場;Workplace","rule ja:規則;rule","Rule ja:規則;Rule",,
	,,| onto34,_onto340,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_property_value_carried.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply($d{'#rule'}->{'#onto34'}, {'@id' => '#_onto340'}, 'property value after a carried property column');
	ok(!exists($d{'#Rule'}->{'#onto34'}), 'carried: not written to the range class');
}

# elementProperty・elementTransitive は予約属性でない（plrDart の追記R983 でやめた）。
# 表に宣言が無ければ、ほかの属性と同じく、ラベルの無い属性として知らせる
run_command('cto.pl',
	"\"]O Org ja:組織;Org\",\\オントロジー,,,\n\"Group ja:群;Group\",\"groupMember ja:構成員;member\",\"Person ja:人;Person\",,\n,,| elementTransitive,true,\n",
	$dir, 'plrTest_element_removed');
like(errorText('plrTest_element_removed'), qr/Warning: property `elementTransitive' .*has no label/,
	'elementTransitive is no longer reserved');

{
	# ObjectProperty の値が選択肢なら、選択肢の1つ（選択肢のクラスの下位）を書ける
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_selector_value');
	"]O W ja:作業場;W",\オントロジー,,,
	Prop,kind(1,_ordered ja:列;ordered,,
	,,_set ja:集合;set,,
	Workplace,rule,Rule,,
	,,| kind,_set,
	Rule,,,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_selector_value.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply($d{'#rule'}->{'#kind'}, {'@id' => '#_set'}, 'selector value');
}

# エラー（出力を作らない）：
# * 選択肢を値域に持つ属性に、選択肢でない値を書く
# * クラスレベルの予約属性を、属性の宣言に書く
# * "| 属性" の属性の所に、表でクラスとして定義した名前を書く
# * 定義域が属性の集まり（ONTO3）の属性を、クラスに書く／定義域がクラスの集まり（ONTO1）の属性を、属性に書く
foreach my $case (
	['plrTest_value_undef', ",,| kind,_sett,\n", 'value not defined in the selector'],
	['plrTest_value_not_option', ",,| kind,Rule,\n", 'value outside the selector'],
	['plrTest_property_value_reserved', ",count(1,integer,| builtInFunction,equal,\n", 'class-level property on a property'],
	['plrTest_property_value_class', ",,| Rule,abc,\n", 'class in "| property"'],
	['plrTest_meta_on_class', "Other,| onto34,_onto340,\n", 'property-level property on a class'],
	['plrTest_meta_on_property', ",count(1,integer,| abstract,true,\n", 'class-level property on a property (by its domain)'],
) {
	my ($prefix, $row, $name) = @$case;
	run_command('cto.pl',
		"\"]O W ja:作業場;W\",\\オントロジー,,,\nProp,kind(1,_ordered ja:列;ordered,,\n,,_set ja:集合;set,,\n"
		. "ONTO3,onto34(1,_onto340,,\n,,_onto342,,\nONTO1,abstract,boolean,,\nWorkplace,rule,Rule,,\n$row",
		$dir, $prefix);
	ok($? != 0 && !-e "$dir/$prefix.jsonld", "error: $name");
}
like(errorText('plrTest_value_not_option'), qr/`Rule' is not in the range/, 'error text: value outside the selector');
like(errorText('plrTest_property_value_class'), qr/class `Rule' in `\| Rule'/, 'error text: class in "| property"');
like(errorText('plrTest_meta_on_class'), qr/property-level property `\| onto34' on a class/, 'error text: property-level property on a class');

{
	# 定義域が属性の集まり（ONTO3）の属性は、属性に書ける（Ontology.xlsx の onto34 の形）
	run_command('cto.pl',
		"\"]O W ja:作業場;W\",\\オントロジー,,,\nONTO3,onto34(1,_onto340,,\n,,_onto342,,\nWorkplace,order,| onto34,_onto340,\n",
		$dir, 'plrTest_meta_on_property_ok');
	my $p = json_file_to_perl("$dir/plrTest_meta_on_property_ok.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply($d{'#order'}->{'#onto34'}, {'@id' => '#_onto340'}, 'property-level property on a property');
}

{
	# クラスの右隣（間に属性の無い所）の予約クラスは、表のクラス #Channel を宣言し、上位を左のクラスと
	# 組込みのクラス（# を付けない Channel）にする（plrDart#511 の行12）。属性の右隣なら値域、
	# A 列なら組込みのクラスそのもの（宣言しない）のまま
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_reserved_sub');
	"]O Sys ja:系;Sys",\オントロジー,,,
	"ONTOc1 ja:チャネルの種類;channel kind","Channel ja:チャネル;Channel",,,
	"Task ja:タスク;Task","channelOf ja:チャネル;channel",Channel,,
	"Channel ja:チャネル;Channel",channelSetting,,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_reserved_sub.jsonld");
	my %byId = map { ($_->{'@id'} // '') => $_ } @{$p->{'defines'}};
	is($byId{'#Channel'}->{'@type'}, 'Class', 'reserved class under a class: #Channel is declared');
	is_deeply([sort map { $_->{'@id'} } @{$byId{'#Channel'}->{'subClassOf'} // []}], ['#ONTOc1', 'Channel'],
		'reserved class under a class: subclass of the class on its left and of the built-in');
	is($byId{'#Channel'}->{'label'}->{'ja'}, "\x{30C1}\x{30E3}\x{30CD}\x{30EB}", 'reserved class under a class: its label is read'); # チャネル
	is($byId{'#channelOf'}->{'range'}, 'Channel', 'reserved class after a property: still the range');
	ok(!exists($byId{'Channel'}) && $byId{'#channelSetting'}->{'domain'} eq 'Channel',
		'reserved class in column A: still the built-in');
	my $c = json_file_to_perl("$dir/plrTest_reserved_subContext.jsonld");
	ok(!exists($c->{'@context'}->[1]->{'Channel'}) && exists($c->{'@context'}->[1]->{'ONTOc1'}),
		'reserved class under a class: its name stays the built-in in the context');
}

done_testing();
