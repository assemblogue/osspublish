#! /usr/bin/perl
use strict;
use IPC::Open2;
use POSIX ':sys_wait_h';
use File::Temp qw/tempdir/;
use JSON::Parse 'json_file_to_perl';
use Test::More tests => 20;

sub run_command {
	my $command = shift;
	my $content = shift;
	my $dir = shift;
	my $prefix = shift;
	my $pid = open2(my $child_in, my $child_out, "$^X ./$command $dir/$prefix $prefix") or die "$!";
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
