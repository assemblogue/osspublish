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

die("usage: cto.pl ontologyName prefix")
    if (@ARGV < 2);

#
# typeMap 生成済みクラス・プロパティを保存　最終出力はこれ
# OMapブロック管理用
#
my @types, %typeMap, @OMap;
my $mode;


# 自動生成クラスのナンバー
# もともとが１行単位の処理なので、他行との関連をたどるのが甚だ困難
my $autoClassCount = 0;

MAIN: {
    parseInput();
    outputOntology($ARGV[0], $ARGV[1]);
}

sub parseInput {
    my $csv = Text::CSV_XS->new({ binary => 1 });
    local $lc;

    my $lastFields;
    while (my $fields = $csv->getline(*STDIN)) {
		$lc++;

		for (my $i = 0; $i < @$fields; $i++) {
			last if ($$fields[$i]);
			$$fields[$i] = $$lastFields[$i];
		}
		$lastFields = $fields;

		extract(@$fields);
    }
}


# 予約語のチェック
# 予約後とマッチしたらその語を返す。マッチしなかった場合、空dataを返す。
sub checkReservedWord {
    # 予約語配列
    my @rsvky = ("string", "integer", "positiveInteger", "nonNegativeInteger", "decimal", "boolean", "dateTime", "mmdata", "date", "plrChannel", "plrSchema", "duration", "time");

    return checkWord(\@rsvky, $_);
}

# 予約クラスのチェック
# 予約クラスとマッチしたらその語を返す。マッチしなかった場合、空dataを返す。
sub checkReservedClass {
    # 予約クラス
    my @rsvcls = ("Channel", "DataSetting");

    return checkWord(\@rsvcls, $_);
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
    my $pcls="", $cls="", $prop="";

	# 自動生成クラスカウンタ
	$autoClassCount = 0;

    foreach $_ (@_) {
		next unless ($_);

		$autoClassCount++;

		if (/^\\.*/) {
			#コメントカラム
		}
		elsif (/^[\]<][ORCTSMDGQL][sSR]?(,*)?/) {
			#Mode 先頭カラムでしか出現しないので、本来、カラム毎にチェックは不要
			my ($kw, $id, $label) = split(/[, \s]+/, $_, 3);
			changeMode($kw, $id, $label);
		}
		elsif ($mode eq "O") {
			# オントロジー定義のみ扱う
			if (checkReservedClass($_)) {
				my ($id) = split(/[ \n]+/, $_, 2);
				# range 一個前のプロパティに設定する
				parsePropertyParams($id, $prop, "ObjectProperty");
			} elsif (/^([a-zA-Z]{2}(_[a-zA-Z]{2})*)?:\n(.*)$/s) {
				# Tooltip
				$prop->{'tooltip'} = {} unless ($prop->{'tooltip'});
				$prop->{'tooltip'}->{$1} = $3;
			}
			#if (/^_?[A-Z]/) {
			elsif (/^_?[A-Z]/ || /^_[a-z]/) {
				# Class
				my ($id, $label) = split(/[ \n]+/, $_, 2);

				$cls = parseClass($id, $label, $pcls);
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
				else {
					# ここは直近のクラス$clsを引数にする
					$prop = parseProperty($id, $label, $cls, $prop);

					# $pclsはクラス間の従属関係なので、間にプロパティ定義が入る場合、クリアする
					$pcls = "";
				}
			} else {
				print STDERR "Error: Bad column `" . encode_utf8($_) . "' at line $lc\n";
				last;
			}

			# print Dumper %typeMap;
		}
    }
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

	# 上位クラスがある場合(上位クラス複数あり得る)
	if ($pcls) {
		setSubClassOf($cls, $pcls->{'@id'});
	}

	$typeMap{$id} = $cls;

    return $cls;
}

# subClassOf にスーパークラスを追加
sub setSubClassOf {
	my ($cls, $pid) = @_;

	# 上位クラスがある場合(上位クラス複数あり得る)
    if ($pid) {
		my %subclassof = (
			'@type' => "Class",
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
					my $atid = generateId("Super", '_SuperClass');
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
            $prop->{'subPropertyOf'} = [$p_prop->{'@id'}];
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
		if ($scofe->{'@type'} ne 'Class') {
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
		if ($scofe->{'@type'} ne 'Class') {
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
			$ll{''} = $elm[0] if ($elm[0] ne "");
		}
		# localつき
		elsif (@elm == 2) {
			$ll{$elm[0]} = $elm[1] if ($elm[1]);
		}
	}

	if (%ll) {
		$type->{$propName} = \%ll;
	}
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
			if ($range eq "boolean") {
				if (lc($val) eq "true") {
					$prop->{'defaultValue'} = JSON::true;
				} else {
					$prop->{'defaultValue'} = JSON::false;
				}
			} elsif (($range eq "decimal") || ($range =~ /integer$/i)) {
				$prop->{'defaultValue'} = numValue($val);
			} else {
				$prop->{'defaultValue'} = $val;
			}
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
