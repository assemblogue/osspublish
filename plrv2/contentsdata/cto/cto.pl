#! /usr/bin/perl
#
# cto.pl phase2
# verion : 1.20
# 2017.12.11
#
use utf8;
use Text::CSV_XS;
use JSON;
use Encode qw/encode_utf8 decode_utf8/;
use Data::Dumper;

# 表だけを読む。ほかのオントロジー（系の Base・Ontology など）は読まない——表で定義するクラス・属性には
# ラベルを付けるので、ラベルの無い名前は、ほかのオントロジーへの参照か書き誤りとして知らせる（checkLabels。
# 橋田さんの決め、plrDart の review 経由、2026-11-16）
die("usage: cto.pl ontologyName prefix\n")
    unless (@ARGV == 2);

#
# typeMap 生成済みクラス・プロパティを保存　最終出力はこれ
# OMapブロック管理用
#
my @types, %typeMap, @OMap;
# "| 属性" で書いた、クラスか属性の宣言の値。全部読んでから属性の定義で型を決める
my @classValues;
# ラベルを添えて定義した属性・クラスの ID（# 付き）。表で定義するクラス・属性にはラベルを付けるので、
# どこにもラベルの無い名前は、ほかのオントロジーで定義されたものへの参照か、書き誤りである（checkLabels）
my %labelledProps;
my %labelledClasses;
# 表に書いたクラス・属性の名前（# を外したもの）→ [種類 'class'・'property', 最初に書いた行]
my %namesWritten;
my @namesWrittenOrder;
# 属性の次の列に書いた、XML Schema の組込のデータ型のうち PLR がサポートしないもの（[名前, 属性の ID, 行]）。
# checkLabels が、ラベルの無い名前とは別の文で知らせる
my @unsupportedRangeNames;
# XML Schema 1.1 の組込のデータ型のうち、予約語（checkReservedWord。PLR が持つデータ型で、plrDart の
# _plr_common の組込のデータ型と同じ集まり）に無いもの。
# 値は、代わりに使う PLR のデータ型（無ければ空）
my %unsupportedXsdDatatypes = (
	"double" => "decimal", "float" => "decimal",
	"long" => "integer", "int" => "integer", "short" => "integer", "byte" => "integer",
	"unsignedLong" => "nonNegativeInteger", "unsignedInt" => "nonNegativeInteger",
	"unsignedShort" => "nonNegativeInteger", "unsignedByte" => "nonNegativeInteger",
	"normalizedString" => "string", "language" => "string",
	"Name" => "string", "NCName" => "string", "NMTOKEN" => "string", "NMTOKENS" => "string",
	"ID" => "string", "IDREF" => "string", "IDREFS" => "string",
	"ENTITY" => "string", "ENTITIES" => "string", "QName" => "string", "NOTATION" => "string",
	"hexBinary" => "", "base64Binary" => "",
	"yearMonthDuration" => "duration", "dayTimeDuration" => "duration",
	"dateTimeStamp" => "dateTime", "anySimpleType" => "", "anyAtomicType" => "",
);
my $mode;


# 自動生成クラスのナンバー
# もともとが１行単位の処理なので、他行との関連をたどるのが甚だ困難
my $autoClassCount = 0;

MAIN: {
    parseInput();
    # linkPath の道の属性も、ラベルの無い名前として数えるので、値を解いてから見る
    resolveClassPropertyValues();
    checkLabels();
    outputOntology($ARGV[0], $ARGV[1]);
}

sub parseInput {
    my $csv = Text::CSV_XS->new({ binary => 1 });
    local $lc;

    my $lastFields;
    while (my $fields = $csv->getline(*STDIN)) {
		$lc++;

		# $own: この行に書かれた最初のカラム（それより左は前の行から引き継いだもの）
		my $own = 0;
		for (my $i = 0; $i < @$fields; $i++) {
			last if ($$fields[$i]);
			$$fields[$i] = $$lastFields[$i];
			$own = $i + 1;
		}
		$lastFields = $fields;

		extract($fields, $lc, $own);
    }
}


# 予約語のチェック
# 予約後とマッチしたらその語を返す。マッチしなかった場合、空dataを返す。
sub checkReservedWord {
    # 予約語配列
    my @rsvky = ("string", "integer", "positiveInteger", "nonNegativeInteger", "decimal", "boolean", "dateTime", "mmdata", "date", "plrChannel", "plrSchema", "duration", "time", "gYear", "gYearMonth", "gMonth", "gDay", "gMonthDay", "anyURI", "nonPositiveInteger", "negativeInteger", "token");
    # token は言語を持たない文字列（ID・コード・実装の名前など）。string の下位ではない（plrDart の追記d61）

    my ($word) = @_;
    return checkWord(\@rsvky, $word);
}

# 系の予約属性のチェック（クラスの "| 属性" で値を書けるメタ属性）。シートに宣言が
# 無くても書く（予約クラスと同じく、宣言は系の側にある）。builtInFunction は文字列、
# linkPath は属性の道（resolveLinkPath。plrDart の追記R971）、aiPrompt は言語ごとの文字列
# （langValueOf。plrDart の追記d60）
sub isReservedProperty {
    my ($id) = @_;
    # 予約属性
    my @rsvprop = ("builtInFunction", "linkPath", "aiPrompt");

    return scalar(grep { $_ eq $id } @rsvprop);
}

# 表に書いたクラス・属性の名前を、最初に書いた行とともに覚える（checkLabels が見る）
sub noteNameWritten {
	my ($kind, $name, $line) = @_;
	return unless (defined($name) && $name ne '');
	return if (exists($namesWritten{$name}));
	$namesWritten{$name} = [$kind, $line];
	push(@namesWrittenOrder, $name);
}

# **表で定義するクラス・属性にはラベルを付ける。** したがって、表のどこにもラベルの無いクラス・属性の
# 名前は、ほかのオントロジーで定義されたものへの参照か、書き誤りである——名前と行を挙げて知らせる
# （属性は値域の列に書いた下位属性の名前と linkPath の道の属性も、クラスは値域・定義域・上位クラスに
# 書いた名前も、同じ1つの決まり）。変換は続ける。値域の列に書いた、PLR がサポートしない XML Schema の
# データ型は、別の文で、代わりのデータ型を添えて知らせる（橋田さんの決め、plrDart の review 経由、2026-11-16）
sub checkLabels {
	my @warnings;
	foreach my $name (@namesWrittenOrder) {
		my ($kind, $line) = @{$namesWritten{$name}};
		if ($kind eq 'class') {
			next if ($labelledClasses{"#$name"} || checkWord(['Channel', 'DataSetting', 'PlrId'], $name));
		}
		else {
			next if ($labelledProps{"#$name"} || isReservedProperty($name));
		}
		push(@warnings, "Warning: $kind `$name' (first written at line $line) has no label in this sheet:"
			. " a reference to another ontology, or a misspelling\n");
	}
	my %seen;
	foreach my $c (@unsupportedRangeNames) {
		my ($id, $prop, $line) = @$c;
		# 同じ名前を、表でクラス・属性として定義していれば、データ型ではない
		next if ($labelledProps{"#$id"} || $labelledClasses{"#$id"});
		next if ($seen{"$prop $id"}++);
		my $instead = $unsupportedXsdDatatypes{$id};
		push(@warnings, "Warning: `$id' in the range of property `$prop' at line $line is an XML Schema datatype"
			. " that PLR does not support" . ($instead ? " (use $instead)" : "") . "\n");
	}
	print STDERR join('', @warnings);
}

# 予約クラスのチェック
# 予約クラスとマッチしたらその語を返す。マッチしなかった場合、空dataを返す。
sub checkReservedClass {
    my ($id) = @_;
    # 予約クラス
    my @rsvcls = ("Channel", "DataSetting", "PlrId");

    return checkWord(\@rsvcls, $id);
}

sub checkWord {
    my ($kwds, $id) = @_;
	foreach my $kwd (@$kwds) {
		if ($id =~ /^$kwd([-+()<>!\s].*|\n|$)/) {
			return $kwd;
		}
	}
	return "";
}


#
# カラムごとの処理
# range が隣カラムになったので、
#　　プロパティカラムの次カラムが
#　　　クラスなら、値域クラス
#　　　予約語なら、プロパティ域値設定
#     プロパティなら、サブプロパティ
#　となる。
sub extract {
    my ($fields, $lc, $own) = @_;

    my $pcls="", $cls="", $prop="", $res;
	# "| 属性" の値を書く宣言：この行で直近のクラスか属性（前の行から引き継いだカラムも
	# 含む）。plrDart の追記R979——属性の集まりの種類（onto34）を属性に書く。
	# カラムを1つ読むたびに、そのカラムで読んだクラスか属性（$res）にする（下の
	# "$decl = $res"）ので、クラス・属性を読む分岐ごとに書かなくてよい
	my $decl;
	# "| 属性" カラムの直後のカラム番号と、その属性
	my $valueCol = -1, $valueProp = "";
	# 前の行から引き継いだ "| 属性" カラムの直後のカラム番号
	my $carriedValueCol = -1;

	# 自動生成クラスカウンタ
	$autoClassCount = 0;

    foreach $_ (@$fields) {
		$autoClassCount++;

		if (($lc == 1) && /^M$/) {
		    $lf = $autoClassCount;
		    last;
		}
		last if ($lf && ($autoClassCount >= $lf));

		if ($autoClassCount - 1 == $carriedValueCol && $autoClassCount - 1 < $own) {
			# 前の行から引き継いだ "| 属性" の値：その行で書いたので、もう扱わない
			next;
		}

		if ($autoClassCount - 1 == $valueCol) {
			# "| 属性" の右隣のカラム：直近のクラスか属性の、その属性の値（"0" も値）
			die("Error: no value for `| $valueProp' at line $lc\n")
				unless (defined($_) && $_ ne '');
			push(@classValues, [$decl, $valueProp, $_, $lc]);
			$valueCol = -1;
			next;
		}

		next unless ($_);

		if (/^\\.*/) {
			#コメントカラム
			$res = undef;
		}
		elsif (/^[\]<][ORCTSMDGQL][sSR]?(,*)?/) {
			#Mode 先頭カラムでしか出現しないので、本来、カラム毎にチェックは不要
			my ($kw, $id, $label) = split(/[, \s]+/, $_, 3);
			changeMode($kw, $id, $label);
		}
		elsif ($mode eq "O") {
			# オントロジー定義のみ扱う
			if (/^\|\s*(\S+)/) {
				# "| 属性"：右隣のカラムが、この行で直近のクラスか属性（$decl）の、
				# その属性の値。前の行から引き継いだカラムなら扱わない（値を二度
				# 書かないため）
				if ($autoClassCount - 1 >= $own) {
					die("Error: `| $1' without class or property at line $lc\n")
						unless ($decl);
					$valueCol = $autoClassCount;
					$valueProp = $1;
				} else {
					$carriedValueCol = $autoClassCount;
				}
			} elsif (($autoClassCount == 1) && checkReservedClass($_)) {
				# A 列の予約クラスは、組込みのクラス（PLR の Channel など）を指す。
				# 宣言はせず、続く欄の属性をそのクラスの属性にする（domain は値域と
				# 同じく # を付けない）。ラベルは組込みのものを使うので読まない（osspublish#3）
				$cls = $res = builtinClass(checkReservedClass($_));
				$pcls = $cls;
			} elsif (($autoClassCount > 1) && $pcls && !$prop && checkReservedClass($_)) {
				# クラスの右隣（間に属性の無い所）の予約クラスは、表のクラス #名前 を宣言する。
				# 上位は、左のクラスと組込みのクラス（# を付けない名前。組込みのものに解決される）。
				# 組込みのクラスは上書きしない（id が違う）。系のオントロジーで、組込みのクラスを
				# 表のクラスの下位に入れるため（Channel を ONTOc1 の下位に。plrDart#511 の行12）。
				# 属性の右隣なら値域（次の分岐）、A 列なら組込みのクラスそのもの（前の分岐）
				my $name = checkReservedClass($_);
				my ($id, $label) = split(/[ \n]+/, $_, 2);
				$cls = $res = parseClass($id, $label, $pcls);
				setSubClassOf($cls, $name);
				$pcls = $cls;
			} elsif (($autoClassCount > 1) && checkReservedClass($_)) {
				my ($id) = split(/[ \n]+/, $_, 2);
				# range 一個前のプロパティに設定する
				parsePropertyParams($id, $prop, "ObjectProperty");
			} elsif (my ($lang, $text) = langValueOf($_)) {
				# Tooltip
				if ($res->{'@id'} =~ /arg[0-9]+/) {
					$res = $cls;
				}
				$res->{'tooltip'} = {} unless ($res->{'tooltip'});
				$res->{'tooltip'}->{$lang} = $text;
			}
			#if (/^_?[A-Z]/) {
			elsif (/^_?[A-Z]/ || /^_[a-z]/) {
				# Class
				my ($id, $label) = split(/[ \n]+/, $_, 2);
				my ($name) = ($id =~ /^([\w\.\-]+)/);
				if ($prop && defined($name) && exists($unsupportedXsdDatatypes{$name})) {
					# 値域の列の、PLR がサポートしない XML Schema のデータ型（Name・ID など大文字で始まるもの）
					push(@unsupportedRangeNames, [$name, $prop->{'@id'}, $lc]);
				}
				else {
					noteNameWritten('class', $name, $lc);
				}

				$cls = $res = parseClass($id, $label, $pcls);
				$pcls = $cls;

				if ($prop) {
					# 域値クラス指定
					setRangeClass($id, $prop);
					$prop = "";
				}
			# } elsif (/^_?[a-z]/) {
			} elsif (/^[a-z]/) {
				# Property
				my ($id, $label) = split(/[ \n]+/, $_, 2);

				if (checkReservedWord($id)) {
					# range 一個前のプロパティに設定する
					parsePropertyParams($id, $prop);
				}
				elsif ($prop && /^([A-Za-z0-9_]+)/ && exists($unsupportedXsdDatatypes{$1})) {
					# XML Schema のデータ型だが PLR がサポートしないもの（下位属性として定義されていれば
					# 数えない。全部読んでから見分ける）。属性としても読む（前と同じ出力にする）
					push(@unsupportedRangeNames, [$1, $prop->{'@id'}, $lc]);
					$prop = $res = parseProperty($id, $label, $cls, $prop);
					$pcls = "";
				}
				else {
					noteNameWritten('property', (/^([A-Za-z0-9_]+)/)[0], $lc);
					# ここは直近のクラス$clsを引数にする
					$prop = $res = parseProperty($id, $label, $cls, $prop);

					# $pclsはクラス間の従属関係なので、間にプロパティ定義が入る場合、クリアする
					$pcls = "";
				}
			} else {
				print STDERR "Error: Bad column `" . encode_utf8($_) . "' at line $lc\n";
				last;
			}
			# このカラムで読んだクラスか属性（組込みのクラス・値域のクラスも）が、続く
			# "| 属性" の値を書く宣言になる。コメント・予約語（値域の型）・tooltip のカラムでは変わらない
			$decl = $res if (ref($res) eq 'HASH' && defined($res->{'@id'}));

			# print Dumper %typeMap;
		}
    }
	die("Error: no value for `| $valueProp' at line $lc\n") if ($valueCol >= 0);
}


# mode: 行頭']'で始まる
#  ]O オントロジー定義
#  ---- ここからスタイルシート関連
#  ]Q 問診
#  ]T タイムライン
#  ]U １日分サマリ
#  ]H 複数日サマリ
#  ]V 図表サマリ
#  ]G グループサマリ
#  ---- ここまで
# サブモード: 現在のmodeに紐つく
#  ]R 限定：Restriction
#  ]C 制約：Constraint
#  ]L レイアウト
#
sub changeMode {
    my ($kw, $id, $label) = @_;
    my $map;

	# 旧仕様('<')対策：先頭の'<'を']'へ
	$kw =~ s/^</\]/;

	if ($kw eq ']O') {
		$mode = "O";
        $map = \@OMap;
	}
	# unknown
	else {
		$mode = "";
		$map = "";
		return;
	}

	# 重複IDチェック
	my $blk;
	foreach $blk (@$map) {
		if ($blk->{'@id'} == $id) {
			return;
		}
	}

	$blk = {
		'@mode' => "$mode",
		'@id' => "$id"
	};

	if ($label) {
		parseLabel($blk, $label);
	}

	push(@$map, $blk);
}

#　クラス解析
# 組込みのクラス（予約クラス）。@types にも Context にも出さない
sub builtinClass {
    my ($id) = @_;

    return { '@id' => $id, 'builtin' => 1 };
}

sub parseClass {
    my ($idParams, $label, $pcls) = @_;

    /.*/;
    $idParams =~ s/^([\w\.\-]+)//;
    my $id = "#$1";

	# 既登録済みか？
    my $cls = $typeMap{$id};
	# 初回登録時のみラベル等を設定する。
    unless ($cls) {
		$cls = {
			'@id' => "$id",
			'@type' => "Class",
		};

		$typeMap{$id} = $cls;
		push(@types, $cls);
    }

	parseClassIdParams($cls, $id, $idParams);
	parseLabel($cls, $label);
	$labelledClasses{$id} = 1 if (defined($label) && $label ne '');

	# 上位クラスがある場合(上位クラス複数あり得る)
	if ($pcls) {
		setSubClassOf($cls, $pcls->{'@id'});
	}

	$typeMap{$id} = $cls;

    return $cls;
}

# 言語ごとの文字列の1つの値（「ja:」と改行の後が本文。言語の無い値は「:」と改行で始まり、
# 鍵は ''）を (言語, 本文) に分ける。この形でなければ空の並び。tooltip と aiPrompt が通る
# （plrDart の追記d60）
sub langValueOf {
	my ($s) = @_;
	return () unless ($s =~ /^([a-zA-Z]{2}(?:_[a-zA-Z]{2})*)?:\n(.*)$/s);
	return (defined($1) ? $1 : '', $2);
}

# クラスか属性の宣言に値を書く（"| 属性" の右隣のカラム）。全部読んだ後に呼ぶ
# （属性の定義が値より後の行にあってもよい）。
# * 系の予約属性（isReservedProperty）は、宣言が無くても reservedPropertyValue の形で書く。
#   予約属性はクラスレベル属性なので、属性の宣言には書けない
# * 表で定義した属性（isDefinedProperty）は、ObjectProperty なら値はクラス等の ID
#   （checkObjectValue で確かめる）、それ以外は値域に合わせる
# * 表で定義していない属性（系の onto34 など。plrDart の追記R979）は、ほかの名前と同じく
#   ラベルの無い属性として知らせ（checkLabels）、値を書く。値域が分からないので、値の綴りが
#   表のクラスの名前の形（# か、_ を除いて大文字で始まる。または _ と小文字で始まる。
#   extract がクラスと読む形）なら ID、ほかは文字列にする。ID の値も、表に定義が無ければ
#   ラベルの無いクラスとして知らせる（osspublish #9 の (b)。橋田さんの決め、2026-11-24）
# * 表でクラスとして定義した名前は属性でないので止める
# **鍵は # 付きの属性 ID にする**（"#builtInFunction" など。plrDart の追記R957）
# ——素の名前で書くと、読む側でオントロジーの ID が前に付き、別の鍵になる
sub resolveClassPropertyValues {
	foreach my $cv (@classValues) {
		my ($cls, $propId, $val, $line) = @$cv;

		# aiPrompt は言語ごとの文字列（tooltip と同じ形。langValueOf）。"| aiPrompt" の行ごとに1つの
		# 言語の値を足す。宣言の有無によらず、いつもこの形で書く（plrDart の追記d60）
		if ($propId eq "aiPrompt") {
			my ($lang, $text) = langValueOf($val);
			die("Error: `| aiPrompt' at line $line must be `lang:' and a newline before the text\n")
				unless (defined($lang));
			$cls->{"#aiPrompt"} = {} unless ($cls->{"#aiPrompt"});
			$cls->{"#aiPrompt"}->{$lang} = $text;
			next;
		}

		if (isReservedProperty($propId) && !isDefinedProperty($propId)) {
			die("Error: class-level property `| $propId' on a property at line $line\n")
				unless (isClassDeclaration($cls));
			$cls->{"#$propId"} = reservedPropertyValue($propId, $val, $line);
			next;
		}

		my $p = $typeMap{"#$propId"};
		die("Error: class `$propId' in `| $propId' at line $line (write a property)\n")
			if ($p && $p->{'@type'} eq "Class");
		unless ($p) {
			noteNameWritten('property', $propId, $line);
			(my $id = $val) =~ s/^#//;
			if ($val =~ /^#/ || $id =~ /^_?[A-Z]/ || $id =~ /^_[a-z]/) {
				noteNameWritten('class', $id, $line);
				$cls->{"#$propId"} = { '@id' => "#$id" };
			} else {
				$cls->{"#$propId"} = $val;
			}
			next;
		}
		checkDeclarationKind($cls, $p, $propId, $line);
		if ($p->{'@type'} eq "ObjectProperty") {
			$val =~ s/^#//;
			checkObjectValue($p, $propId, $val, $line);
			$cls->{"#$propId"} = { '@id' => "#$val" };
		} else {
			$cls->{"#$propId"} = valueOfRange($p->{'range'}, $val);
		}
	}
}

# 宣言 [$decl] がクラスの宣言か（組込みのクラスも。ほかは属性の宣言）
sub isClassDeclaration {
	my ($decl) = @_;
	return ($decl->{'builtin'} || ($decl->{'@type'} // '') eq "Class");
}

# 表で定義した属性 [$p]（"| $propId"）の定義域が、クラスの集まり（#ONTO1）か属性の集まり（#ONTO3）か、
# その下位なら、値を書く宣言 [$decl] はそれぞれクラスか属性でなければならない（Ontology.xlsx で、
# 属性のメタ属性 onto34 をクラスに書く、などの書き違いで止める。予約属性を属性に書いたときと対）。
# 定義域がほかのクラスなら見ない
sub checkDeclarationKind {
	my ($decl, $p, $propId, $line) = @_;
	my $domain = $p->{'domain'};
	return unless (defined($domain) && !ref($domain));
	die("Error: property-level property `| $propId' on a class at line $line\n")
		if (isSubClassOrSelf($domain, "#ONTO3") && isClassDeclaration($decl));
	die("Error: class-level property `| $propId' on a property at line $line\n")
		if (isSubClassOrSelf($domain, "#ONTO1") && !isClassDeclaration($decl));
}

# ObjectProperty [$p]（"| $propId"）の値 [$val]（# を外した ID）を確かめる——書き違い
# （"_onto34" など）で止める：
# * 属性の値域が選択肢のクラス（setRangeClass が作る _AutomaticGeneration_…_SelectorClass）
#   なら、値はその選択肢（その下位のクラス）でなければならない。ほかの値域（compensatesWith
#   の ONTO1 など、値がクラスそのものであるもの）では、下位かを見ない
# * 表に定義の無い値は、ほかの名前と同じく、ラベルの無いクラスとして知らせる（checkLabels）
sub checkObjectValue {
	my ($p, $propId, $val, $line) = @_;
	(my $range = $p->{'range'} // '') =~ s/^#//;
	if ($range =~ /^_AutomaticGeneration_.*_SelectorClass$/ && $typeMap{"#$range"}) {
		die("Error: `$val' is not in the range `$range' of `| $propId' at line $line\n")
			unless (isSubClassOrSelf("#$val", "#$range"));
		return;
	}
	noteNameWritten('class', $val, $line);
}

# クラス [$id] が [$super] か、その下位（subClassOf をたどる。表の定義だけを見る）か
sub isSubClassOrSelf {
	my ($id, $super) = @_;
	my %seen;
	my @queue = ($id);
	while (@queue) {
		my $c = shift(@queue);
		next if ($seen{$c}++);
		return 1 if ($c eq $super);
		my $cls = $typeMap{$c} or next;
		foreach my $s (@{$cls->{'subClassOf'} || []}) {
			push(@queue, $s->{'@id'}) if (ref($s) eq 'HASH' && $s->{'@id'});
		}
	}
	return 0;
}

# 系の予約属性 [$propId] の値 [$val] を、書き出す形にする：
# * builtInFunction：文字列のまま
# * linkPath：属性の道（resolveLinkPath。plrDart の追記R971・R972）
# （elementProperty・elementTransitive は plrDart の追記R983 でやめた——要素は、クラスが
# 制限で持つと宣言した hasElement の下位属性で決まる）
# aiPrompt は言語ごとの文字列なので、resolveClassPropertyValues が先に扱う
sub reservedPropertyValue {
	my ($propId, $val, $line) = @_;
	return resolveLinkPath($val, $line) if ($propId eq "linkPath");
	return $val;
}

# 属性 [$id]（# を外したもの）が、表で定義されているか。クラスの ID は属性ではない
sub isDefinedProperty {
	my ($id) = @_;
	my $p = $typeMap{"#$id"};
	return ($p && $p->{'@type'} ne "Class");
}

# linkPath の値（arg1 から arg2 へたどる属性の ID を空白で区切った並び。逆向きに
# たどる属性には - を付ける）を、歩みの @list にする（plrDart の追記R971・R972）。
# 歩みの形は SHACL の属性の道に合わせ、順向きは属性の ID、逆向きは inversePath で包む。
# 例："truthValue -isTrue" →
#   {"@list": [{"@id": "#truthValue"}, {"inversePath": {"@id": "#isTrue"}}]}
# 関係のノード自身の位置の印「|」は、並びの中の文字列 "|" にする。例："onto5 | ontoA" →
#   {"@list": [{"@id": "#onto5"}, "|", {"@id": "#ontoA"}]}
# 道の形の誤り（空の道・- の後に何も無い・属性の所にクラスの名前）はエラーで止める。道の属性に表の中の
# ラベルの定義が無ければ、ほかの名前と同じく、ラベルの無い属性として知らせる（noteNameWritten・checkLabels）
sub resolveLinkPath {
	my ($val, $line) = @_;
	my @steps;
	my $bars = 0;
	foreach my $s (split(/\s+/, $val)) {
		next if ($s eq '');
		# 「|」は属性でなく、関係のノード自身の位置の印（plrDart：橋田さんの決め 11/27）。並びの中の文字列 "|"
		# として書き出す。2つの属性の間にだけ来て、1つの道に多くても1つ
		if ($s eq '|') {
			die("Error: `|' at the head of `| linkPath' at line $line (write it between two properties)\n")
				unless (@steps);
			die("Error: more than one `|' in `| linkPath' at line $line\n") if ($bars++);
			push(@steps, '|');
			next;
		}
		my $inverse = ($s =~ s/^-//);
		$s =~ s/^#//;
		die("Error: no property after `-' in `| linkPath' at line $line\n")
			if ($s eq '');
		my $p = $typeMap{"#$s"};
		# 表でクラスとして定義した名前は止める。表に無い名前は、系のクラスか書き誤りかは分からないので、
		# ほかの名前と同じく、ラベルの無い属性として知らせる（綴りでは見分けない）
		die("Error: class `$s' in `| linkPath' at line $line (write a property)\n")
			if ($p && $p->{'@type'} eq "Class");
		noteNameWritten('property', $s, $line);
		my $step = { '@id' => "#$s" };
		push(@steps, $inverse ? { 'inversePath' => $step } : $step);
	}
	die("Error: no property in `| linkPath' at line $line\n") unless (@steps);
	die("Error: `|' at the tail of `| linkPath' at line $line (write it between two properties)\n")
		if ($steps[-1] eq '|');
	return { '@list' => \@steps };
}

# subClassOf にスーパークラスを追加
sub setSubClassOf {
	my ($cls, $pid) = @_;

	# 上位クラスがある場合(上位クラス複数あり得る)
    if ($pid) {
		# 上位クラスは素の参照 {"@id": …} で書く（参照に属性を添えない。plrDart の追記d119）。
		# subClassOf の値で @type を持つのは限定（Restriction）だけ
		my %subclassof = (
			'@id' => $pid,
			);

		my $scof = $cls->{'subClassOf'};
		unless ($scof) {
			#  新規作成：Jacksonの都合、１個でも[ ]で囲む。
			$cls->{'subClassOf'} = [ \%subclassof ];
			return;
		}

		my $dpl = detectDuplicate($pid, $scof);
		if ($dpl == 0) {
			#　重複がなければ追加
			push(@$scof, \%subclassof);
		}
    }
}

# 重複IDの検出
#　subClassOfの{'@id':name'},{...}...形式を想定
#  重複があれば1(true)、なければ0(false)
sub detectDuplicate {
    my ($id, $scof) = @_;

	foreach  my $elm (@$scof) {
		if ($id eq $elm->{'@id'}) {
			return 1; # true
		}
	}

	return 0; # false
}

#　プロパティ解析
sub parseProperty {
    my ($idParams, $label, $cls, $p_prop) = @_;

    /.*/;

	# idは小文字始まりで、大文字小文字入りまじり
	# 先頭小文字のチェックは上位処理で行っているので、ここでは気にしない
    # id名の直後に@属性の型がつくので、@もマッチング文字とする 2017/07/31 Kaneko
    $idParams =~ s/^([a-zA-Z0-9_@]+)//;
    #my $id = "#$1";

	## id部分を@で分割し、idと属性の型に分ける
    $propType = "$1";
    $propType =~ s/^([a-zA-Z0-9_]+)//;
    $id = "#$1";
    $propType =~ s/^@//;
    $labelledProps{$id} = 1 if (defined($label) && $label ne '');

    my $prop = $typeMap{$id};
    if ($prop) {
		#　既に登録済のプロパティ名
		#if ($params) {
		#	print STDERR "Warning: Property `$id' was already defined " .
		#		"at line $lc\n";
		#}

		if ($cls) {
			parsePropertyIdParams($cls, $id, $idParams);

			# domain調整
			# 共通のスーパークラスをdomainとする。
			my $domain = $prop->{'domain'};

			unless ($domain) {
				# domain未設定なら現クラスIDを設定
				$prop->{'domain'} = $cls->{'@id'};
			}
			elsif ($domain =~ /^#_AutomaticGeneration_+.*/) {
				# 既にdomainが自動生成クラスである場合 subClassOf 追加
				setSubClassOf($cls, $domain);
				$typeMap{$cls->{'@id'}} = $cls;
			}
			else {
				# 共通domainを探す
				my $cmn_domain = checkDomain($domain, $cls);
				if ($cmn_domain) {
					$prop->{'domain'} = $cmn_domain;
				}
				else {
					# 共通のクラスが無い場合、新しいクラスを生成する。
					# 名前は、定義域を作った属性の id と表（ファイル）の名前から作る——列の位置（generateId）で付けると、
					# 別の属性の和や別の表の和が同じ名前になり、読み手が1つのクラスに合わせて定義域を誤る（assemblogue/plrDart#746 の続きの調べ）
					my $atid = generateDomainId($prop->{'@id'});
					# 自動生成クラスを新規登録(既にあっても問題なし)
					my $ncls = parseClass($atid, "", "");

					# それぞれのsubClassOfに自動生成クラスを追加
					setSubClassOf($cls, $ncls->{'@id'});
					$typeMap{$cls->{'@id'}} = $cls;

					my $pcls = $typeMap{$domain};
					setSubClassOf($pcls, $ncls->{'@id'});
					##$typeMap{$domain} = $pcls;

					# domain指定
					$prop->{'domain'} = $ncls->{'@id'};
				}
			}
		}

        if ($p_prop) {
            # 属性の木の2か所以上に書いた属性は、上位をそれぞれ足す（後の方で上書きしない）
            my $sp = $prop->{'subPropertyOf'} || [];
            $sp = [$sp] unless ref($sp) eq 'ARRAY';
            push(@$sp, $p_prop->{'@id'}) unless grep { $_ eq $p_prop->{'@id'} } @$sp;
            $prop->{'subPropertyOf'} = $sp;
        }

		## $typeMap{$id} = $prop;

		return $prop;
    }

    $prop = {
		'@id' => "$id",
    };

    parseLabel($prop, $label);

	#  従属クラスの指定と、制約を従属クラスに登録
    if ($cls) {
		$prop->{'domain'} = $cls->{'@id'};
		parsePropertyIdParams($cls, $id, $idParams)
    }

    # 従属プロパティの指定
    if ($p_prop) {
        $prop->{'subPropertyOf'} = [$p_prop->{'@id'}];
    }

    # 属性の型指定がある
    if ($propType) {
		$prop->{'@type'} = $propType;
	}

    unless ($prop->{'@type'}) {
		$prop->{'@type'} = "Property";
    }

    $typeMap{$id} = $prop;
    push(@types, $prop);

    return $prop;
}

#　共通ドメインの探索
sub checkDomain {
    my ($domain, $cls) = @_;

	my $rt = searchDomain($domain, $cls);
	if ($rt) {
		return $rt;
	}

	my $pcls = $typeMap{$domain};
	unless ($pcls) {
		return "";
	}

	my $scof = $pcls->{'subClassOf'};
	foreach my $scofe (@$scof) {
		if ($scofe->{'@type'}) {	# 限定は飛ばす（上位クラスは素の参照）
			next;
		}

		$domain = $scofe->{'@id'};
		$rt = checkDomain($domain, $cls);
		if ($rt) {
			return $rt;
		}
	}

	return "";
}

#　親クラスを遡り、共通クラスを探す
sub searchDomain {
    my ($domain, $cls) = @_;

	if ($domain eq $cls->{'@id'}) {
		return $domain;
	}

	# サブクラスを探索
	$scof = $cls->{'subClassOf'};

	foreach my $scofe (@$scof) {
		if ($scofe->{'@type'}) {	# 限定は飛ばす（上位クラスは素の参照）
			next;
		}

		my $id = $scofe->{'@id'};
		if ($id eq $domain) {
			return $domain;
		}

		# さらにサブクラスを探索
		my $pcls = $typeMap{$id};
		if ($pcls) {
			$rt =  searchDomain($domain, $pcls);
			if ($rt) {
				return $rt;
			}
		}
	}

	return "";
}

# ラベルの解析（ブロック、クラス、プロパティ共通）
sub parseLabel {
    my ($type, $label) = @_;

    # Label|Abbreb|Comment|Format|image
	my @name = ("label","abbrev","comment","format","image");

	# 改行を廃し、'|'で切り分ける
	$label =~ s/\n//;
    my @la = split(/\|/, $label, @name);

	my $i = 0;
	foreach  my $ky (@name) {
		if ($la[$i] ne "") {
			parseLabelLang($type, $la[$i], $ky);
		}

		$i++;
	}
}

sub parseLabelLang {
	my ($type, $label, $propName) = @_;

	my %ll;

	# local毎に分解 (local:string;...)[]
	my @l = split(/;/, $label);

	foreach $lcl (@l) {

		$lcl =~ s/\n//;

		# localと本文に分解
		my @elm = split(/:/, $lcl, 2);

		# localが無い
		if (@elm == 1) {
			$ll{''} = processPercent($elm[0]) if ($elm[0] ne "");
		}
		# localつき
		elsif (@elm == 2) {
			$ll{$elm[0]} = processPercent($elm[1]) if ($elm[1]);
		}
	}

	if (%ll) {
		$type->{$propName} = \%ll;
	}
}

sub processPercent {
    my ($str) = @_;
    $str =~ s/^%//;

    return $str;
}

sub parseClassIdParams {
    my ($cls, $id, $idParams) = @_;

    while ($idParams) {
	/.*/;
	$idParams =~ s/^([!=(<])(\d*)//;

	unless ($1) {
	    print STDERR
		"Error: Undetermined class symbol `$idParams' " .
		"on class `$id at line $lc\n";
	    last;
	}

	if ($1 eq "!") {
	    # selected
	    $cls->{'selected'} = JSON::true;
	    return;
	} else {
		my $num = $2;
		my $n;
		if ($1 eq "=") {
			$n = "classCardinality";
		} elsif ($1 eq "(") {
			$n = "maxClassCardinality";
		} elsif ($1 eq "<") {
			$n = "maxClassCardinality";
			$num++;
		}
		$cls->{$n} = $num + 0;
	}
    }
}

# プロパティIDパメラータの解析と
# 従属クラスのsubClassOfへRestrictionの追記を行う。
# 従属クラスに既に同名のRestriction定義がある場合、0(false)を返す
sub parsePropertyIdParams {
    my ($cls, $id, $idParams) = @_;

	# 既に同名Restrictionが存在する
    my $scofa = $cls->{'subClassOf'};
	if ($scofa) {
		foreach $scofe (@$scofa) {
			if ($scofe->{'onProperty'} eq "$id") {
				return 0; # false;
			}
		}
	}

	my %restriction = (
		'@type' => "Restriction",
		'onProperty' => "$id",
    );

	$DB::single = 1;

    while ($idParams) {
		/.*/;
		$idParams =~ s/^([!*\/=()<>])([\d\w]*)//;
        # $1:記号　$2:値 数字か文字（[0-9][a-z][A-Z])

		unless ($1) {
			print STDERR
				"Error: Undetermined restriction symbol `$idParams' " .
				"on property `$id at line $lc\n";
			last;
		}

		if ($1 eq "*") {
			# no restriction.
			return;
		} elsif ($1 eq "/") {
			# Not appear on input form.
			$restriction{'invisible'} = JSON::true;
		} elsif ($1 eq "!") {
            # 直後にはデフォルト値は来ない
			# $restriction{'defaultValue'} = $2;
		} else {
			unless (length($2)) {
				print STDERR "Error: No number parameter " .
					"on property `$id' of restriction `$1' at line $lc\n";
				last;
			}
			my $num = $2;

			my $n;
			if ($1 eq "=") {
				$n = "cardinality";
			} elsif ($1 eq ")") {
				$n = "minCardinality";
			} elsif ($1 eq ">") {
				$n = "minCardinality";
				$num++;
			} elsif ($1 eq "(") {
				$n = "maxCardinality";
			} elsif ($1 eq "<") {
				$n = "maxCardinality";
				$num++;
			}
			$restriction{$n} = $num + 0;
		}
    }

	if ($cls->{'builtin'}) {
		# 組込みのクラスには制約を書き足せない
		print STDERR "Warning: Restriction on property `$id' of built-in class " .
			"`$cls->{'@id'}' is ignored at line $lc\n"
			if (keys(%restriction) > 2);
		return 0;
	}

	# 常に [ ] とする
    my $scof = $cls->{'subClassOf'};
    unless ($scof) {
		$cls->{'subClassOf'} = [ \%restriction ];
		return 1; # true;
    }

    push(@$scof, \%restriction);

	return 1; # true;
}


#  自動生成クラス名: idとカラム位置で特定
sub generateId {
	my ($id, $postwd) = @_;

	$acc = sprintf("%010d", $autoClassCount);
	$atcls = $id . '_' . $acc . $postwd;
	$atcls =~ s/^#//;
	$atcls = '_AutomaticGeneration_' . $atcls;

	return $atcls;
}

#  定義域の和の自動生成クラス名: 表（ファイル）の名前と、定義域を作った属性の id で特定する
sub generateDomainId {
	my ($propId) = @_;

	my $p = $propId;
	$p =~ s/^#//;
	$p =~ s/[^A-Za-z0-9_]/_/g;
	my $file = $ARGV[0];
	$file =~ s{.*/}{};
	$file =~ s/[^A-Za-z0-9_]/_/g;

	return '_AutomaticGeneration_Super_' . $file . '_' . $p;
}

#　プロパティの値域(range)へクラスをセット
sub setRangeClass {
	my ($idParams, $prop) = @_;

	/.*/;
	$idParams =~ s/^(\w+)//;
	my $cls_id = $1;
	my $prop_id = $prop->{'@id'};

	my $c_range = $prop->{'range'};
	if ($c_range) {
		#range設定あり

		if (checkReservedWord($c_range)) {
			# 既にデータタイプとして設定されている場合
			print STDERR "Warning: Property $prop_id is DatatypeProperty that already have a range.\n";
			return;
		}

		if ($c_range eq "#$cls_id") {
			# 同名クラスが値域となっているなら、何もしなくてよい。
			return;
		}

		if ($c_range =~ /^#[_A-Z0-9]+?/) {
		#if ($c_range =~ /^#_[A-Z0-9]+?/) {
			# 選択肢クラスが設定されている。
			#if ($cls_id =~ /^[A-Z0-9]+?/) {
			#	# 選択肢クラスの代わりに通常クラスを設定しようとした。
			#	print STDERR "Warning: Property $prop_id is DatatypeProperty that already have a range(Class-Selector).\n";
			#	return;
			#}

			#  自動生成クラス名: プロパティ名とカラム位置で特定
			$atid = generateId($prop->{'@id'}, '_SelectorClass');

			# 自動生成クラスはプロパティdomainをスーパークラスとする
			my $domain_name = $prop->{'domain'};
			my $domain_cls = $typeMap{"$domain_name"};

			# 自動生成クラスを新規登録(既にあっても問題なし)
		    ## $pcls = parseClass($atid, "", $domain_cls);  2017.11.15 autogeneration classは単独クラスとする
			$pcls = parseClass($atid, "", "");

			# 追加するクラスは、自動生成クラスのサブクラス
			parseClass($cls_id, "", $pcls);

			# 既にrangeが自動生成クラス
			if ($c_range eq "#$atid") {
				return;
			}

			# 新規に自動生成クラスを生成した場合、
			# 現在rangeに設定されているクラスを自動生成クラスへ登録
			$pcls = $typeMap{"#$atid"};
			$c_range =~ s/^#//;
			parseClass($c_range, "", $pcls);
			$cls_id = $atid;
		}
		else {
			# 非選択肢クラスが設定されている。
			print STDERR "Warning: Property $prop_id is DatatypeProperty that already have a range(Class).\n";
			return;
		}
	}

	$prop->{'range'} = "#$cls_id";
	$prop->{'@type'} = "ObjectProperty";
    ## $typeMap{$prop_id} = $prop;
}

#　値域のセット
sub parsePropertyParams {
    my ($params, $prop, $type) = @_;

    my ($range, $params1) = split(/[-+=@|!()<>]/, $params, 2);
    $params = $_;
	$params =~ s/$range//;
	$params =~ s/\s//;  #パラメータ部にホワイトスペースは不要（あるとエラーになるので削除）

    if ($range) {
		$prop->{'range'} = $range;
	}

    while ($params) {
		/.*/;

		my $delim = "=@!()<>";
		if( $range eq "boolean" ){
			$delim = "-+" . $delim;
		}

		$params =~ s/^([${delim}])([^${delim}]+)//;

		unless ($1) {
			print STDERR "Error: Undetermined property type symbol `$params' " .
				"on property `$id at line $lc\n";
			last;
		}

		# マッチングでクリアされるので一旦別変数へ
		my $sym = $1;
		my $val = $2;

		if ($sym eq "=") {
			# range.
			$prop->{'range'} = $range = $val;
		} elsif ($sym eq "@") {
			# type.
			$prop->{'@type'} = $val;
		} elsif ($sym eq "+") {
			# '|'で切り分ける
		my @la = split(/\|/, $val);
			# trueLabel.
			parseLabelLang($prop, $la[0], 'trueLabel');
			if( $#la > 0 ){
				parseLabelLang($prop, $la[1], 'trueAbbrev');
			}
		} elsif ($sym eq "-") {
			# '|'で切り分ける
		my @la = split(/\|/, $val);
			# falseLabel.
			parseLabelLang($prop, $la[0], 'falseLabel');
			if( $#la > 0 ){
				parseLabelLang($prop, $la[1], 'falseAbbrev');
			}
		} elsif ($sym eq "!") {
			# defaultValue.
			$prop->{'defaultValue'} = valueOfRange($range, $val);
		} elsif ($sym eq "(") {
			$prop->{'maxInclusive'} = numValue($val);
		} elsif ($sym eq "<") {
			$prop->{'maxExclusive'} = numValue($val);
		} elsif ($sym eq ")") {
			$prop->{'minInclusive'} = numValue($val);
		} elsif ($sym eq ">") {
			$prop->{'minExclusive'} = numValue($val);
		}
    }

    ## 特に設定されていないなら
    #my $ptp = $prop->{'@type'};
    #unless ($ptp) {
	$prop->{'@type'} = $type || "DatatypeProperty";
    #}

	## my $prop_id = $prop->{'@id'};
    ## $typeMap{$prop_id} = $prop;

	return $prop;
}

# 値域に合わせた値（真偽値・数はその型、それ以外は文字列）
sub valueOfRange {
	my ($range, $val) = @_;

	if ($range eq "boolean") {
		return (lc($val) eq "true") ? JSON::true : JSON::false;
	} elsif (($range eq "decimal") || ($range =~ /integer$/i)) {
		return numValue($val);
	}
	return $val;
}

sub numValue {
    my ($val) = @_;
    $val =~ s/^\s*~/-/g;

    return $val + 0;
}

sub outputOntology {
    my ($ontologyName, $prefix) = @_;

#    my $json = JSON->new->pretty;
    my $json = JSON->new->pretty->canonical;
	my $idname = "";
	my $label = "";
	my $abbrev = "";
    die("Error: failed to open file `$ontologyName.jsonld': $!\n")
	unless (open(F, ">$ontologyName.jsonld"));

	#  オントロジー ID label
	foreach my $omap (@OMap) {
		$idname = $omap->{'@id'};
		$label = $omap->{'label'};

		if ($omap->{'abbrev'}) {
			$abbrev = $omap->{'abbrev'};
		}

		last if ($idname);
		# 現在は１ファイルにオントロジーは１ブロックとする
	}

	my $oj = {
		'@context' => "http://PUBLIC/ontologies/menuContext.jsonld",
		'@id' => "$idname",
		'@type' => 'PlrOntology',
		'label' => \%$label,
		'defines' => \@types,
	};

	if ($abbrev) {
		$oj->{'abbrev'} = \%$abbrev;
	}

	# オントロジーJSON-LD
#    print F encode_utf8($json->encode({
#	'@context' => "http://PUBLIC/ontologies/menuContext.jsonld",
#	'@id' => "$idname",
#	'@type' => 'Ontology',
#	'label' => \%$label,
#	'defines' => \@types,
#    }));
    print F encode_utf8($json->encode($oj));
    close(F);

	#
    my %myContext = ( $prefix => "./$ontologyName.jsonld" );

    foreach $t (@types) {
	my $id = $t->{'@id'};
	$id =~ s/^#//;

	if ($t->{'@type'} eq 'Class') {
	    # 予約クラスの名前（Channel など）は組込みのクラスを指すので、表のクラス #Channel に向けない
	    next if (checkReservedClass($id) eq $id);
	    $myContext{$id} = "$prefix:$id";
	} else {
	    if ($t->{'range'} =~ /#?_?[A-Z]/) {
		$type = '@id';
	    } else {
		$type = getRange($t);
		unless ($type) {
		    $type = "string";
		}
	    }

	    $myContext{$id} = {
		'@id' => "$prefix:$id",
		'@type' => $type,
	    };
	}
    }

    die("Error: failed to open file `$ontologyName.jsonld': $!\n")
	unless (open(F, ">${ontologyName}Context.jsonld"));

    print F encode_utf8($json->encode({
	'@context' => [
	    "http://PUBLIC/ontologies/menuContext.jsonld",
	    \%myContext,
	],
    }));
    close(F);
}

sub getRange {
    my ($prop) = @_;

    my $range = $prop->{'range'};

    if ($range =~ /#?_?[A-Z]/) {
	return '@id';
    }

    if ($range) {
	return $range;
    }

    my @sp;
    my $spof = $prop->{'subPropertyOf'};
    if ($spof) {
	if (ref($spof) ne "ARRAY") {
	    $sp[0] = $spof;
	} else {
	    @sp = @$spof;
	}
    }

    foreach my $p (@sp) {
	my $r = getRange($p);
	if ($r) {
	    return $r;
	}
    }
}

# end of file
