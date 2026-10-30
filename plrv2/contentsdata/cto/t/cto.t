#! /usr/bin/perl
use strict;
use IPC::Open2;
use POSIX ':sys_wait_h';
use File::Temp qw/tempdir/;
use JSON::Parse 'json_file_to_perl';
use Test::More tests => 38;

sub run_command {
	my $command = shift;
	my $content = shift;
	my $dir = shift;
	my $prefix = shift;
	# 残りの引数は系のオントロジーのファイル
	my $pid = open2(my $child_in, my $child_out, join(' ', "$^X ./$command $dir/$prefix $prefix", @_)) or die "$!";
	print $child_out $content;
	close $child_in;
	close $child_out;
	waitpid $pid, 0;
	return $dir;
}

my $dir = tempdir('/tmp/plrtest_XXXX');

# 系のオントロジー（linkPath の道の属性を確かめるのに渡す。plrDart の
# sample/system/Ontology.jsonld の形を小さくしたもの）
my $systemOntology = "$dir/plrTest_system.jsonld";
{
	open(my $f, '>', $systemOntology) or die "$!";
	print $f '{"@id": "ONTO", "defines": [{"@id": "#truthValue", "@type": "ObjectProperty"},'
		. ' {"@id": "#onto34", "@type": "ObjectProperty"},'
		. ' {"@id": "#Constraint", "@type": "Class"}]}';
	close($f);
}

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
	# 包む）にする。道の属性は、シートか、引数で渡した系のオントロジーで
	# 定義されているもの
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_link_path', $systemOntology);
	"]O DG ja:議論;DG",\オントロジー,,,
	Issue,conjSubIssue,Issue,,
	Answer,isTrue,boolean,,
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
}

# linkPath の道に、定義の無い属性やクラスを書くとエラー（出力を作らない）。系の
# オントロジーを渡さなければ、系の属性も定義の無い属性になる
foreach my $case (
	['plrTest_link_path_undef', ",Typo,| linkPath,truthValue -conjSubIsue,\n", 'undefined property in linkPath', $systemOntology],
	['plrTest_link_path_class', ",Cls,| linkPath,Issue,\n", 'class in linkPath', $systemOntology],
	['plrTest_link_path_sysclass', ",SysCls,| linkPath,Constraint,\n", 'system class in linkPath', $systemOntology],
	['plrTest_link_path_nosys', ",Sys,| linkPath,truthValue,\n", 'system property without the system ontology'],
) {
	my ($prefix, $row, $name, @system) = @$case;
	run_command('cto.pl',
		"\"]O DG ja:議論;DG\",\\オントロジー,,,\nIssue,conjSubIssue,Issue,,\nGraphRelation,,,,\n$row",
		$dir, $prefix, @system);
	ok($? != 0 && !-e "$dir/$prefix.jsonld", "error: $name");
}

{
	# 系の予約属性 elementProperty・elementTransitive（plrDart の追記R974）：
	# 要素を持つ属性の ID（シートか系の属性）は {"@id": "#…"} に、入れ子を
	# たどるかは真偽値にする
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_element', $systemOntology);
	"]O Org ja:組織;Org",\オントロジー,,,
	Group,groupMember,Person,,
	,NestedGroup,| elementProperty,groupMember,
	,,| elementTransitive,TRUE,
	,FlatGroup,| elementProperty,#truthValue,
	,,| elementTransitive,false,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_element.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply([$d{'#NestedGroup'}->{'#elementProperty'}, $d{'#FlatGroup'}->{'#elementProperty'}],
						[{'@id' => '#groupMember'}, {'@id' => '#truthValue'}],
						'elementProperty is the id of a sheet or system property');
	ok($d{'#NestedGroup'}->{'#elementTransitive'} && !$d{'#FlatGroup'}->{'#elementTransitive'},
		 'elementTransitive is a boolean');
	open(my $f, '<', "$dir/plrTest_element.jsonld") or die "$!";
	my $text = do { local $/; <$f> };
	like($text, qr/"#elementTransitive"\s*:\s*true\b.*"#elementTransitive"\s*:\s*false\b|"#elementTransitive"\s*:\s*false\b.*"#elementTransitive"\s*:\s*true\b/s,
			 'elementTransitive is written as JSON true and false');
	ok(!exists($d{'#elementProperty'}) && !exists($d{'#elementTransitive'}),
		 'elementProperty and elementTransitive are not declared');
}

# elementProperty に定義の無い属性やクラス、elementTransitive に真偽値でないものを
# 書くとエラー（出力を作らない）
foreach my $case (
	['plrTest_element_undef', ",Typo,| elementProperty,groupMembr,\n", 'undefined property in elementProperty'],
	['plrTest_element_class', ",Cls,| elementProperty,Group,\n", 'class in elementProperty'],
	['plrTest_element_bool', ",Bad,| elementTransitive,yes,\n", 'non-boolean elementTransitive'],
) {
	my ($prefix, $row, $name) = @$case;
	run_command('cto.pl',
		"\"]O Org ja:組織;Org\",\\オントロジー,,,\nGroup,groupMember,Person,,\n$row",
		$dir, $prefix, $systemOntology);
	ok($? != 0 && !-e "$dir/$prefix.jsonld", "error: $name");
}

{
	# "| 属性" は、この行で直近のクラスか属性の宣言に書く（plrDart の追記R979——
	# 属性の集まりの種類 onto34 を属性に書く）。前の行から引き継いだ属性のカラムの
	# 後にも書ける。系のオントロジーで定義されたメタ属性（onto34）も書ける
	run_command('cto.pl', <<~'EOD', $dir, 'plrTest_property_value', $systemOntology);
	"]O W ja:作業場;W",\オントロジー,,,
	Workplace,rule,Rule,,
	,,| onto34,_onto340,
	,count(1,integer,| onto34,_onto342,
	Rule,,,,
	EOD
	my $p = json_file_to_perl("$dir/plrTest_property_value.jsonld");
	my %d = map { ($_->{'@id'} => $_) } @{$p->{'defines'}};
	is_deeply([$d{'#rule'}->{'#onto34'}, $d{'#count'}->{'#onto34'}],
						[{'@id' => '#_onto340'}, {'@id' => '#_onto342'}],
						'property value on a property (carried and same row)');
	ok(!exists($d{'#Workplace'}->{'#onto34'}) && !exists($d{'#Rule'}->{'#onto34'}),
		 'property value is not written to the class');
}

# 属性の宣言に書く値：系を渡さなければ onto34 は定義の無い属性、クラスレベルの
# 予約属性は属性の宣言に書けない（出力を作らない）
foreach my $case (
	['plrTest_property_value_nosys', ",count(1,integer,| onto34,_onto340,\n", 'meta property on a property without the system ontology'],
	['plrTest_property_value_reserved', ",count(1,integer,| builtInFunction,equal,\n", 'class-level property on a property', $systemOntology],
) {
	my ($prefix, $row, $name, @system) = @$case;
	run_command('cto.pl',
		"\"]O W ja:作業場;W\",\\オントロジー,,,\nWorkplace,rule,Rule,,\n$row",
		$dir, $prefix, @system);
	ok($? != 0 && !-e "$dir/$prefix.jsonld", "error: $name");
}

# 書き違いの属性・値の無い "| 属性" はエラー（出力を作らない）
foreach my $case (
	['plrTest_classvalue_undef', ",Typo,| cuont,X,\n", 'undefined property'],
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

done_testing();
