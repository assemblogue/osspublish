#! /usr/bin/perl

#$DB::single=1;
#perl -d hogehoge

#
# cts.pl version.1.11
#  スタイルシート変換ツール
# 2018.11.12
#
#　スプレッドシートから生成したcsvからjsonld形式データに変換する。
#　スタイルシート定義部分のみを扱う。
#
use utf8;
use Text::CSV_XS;
use JSON;
use Encode qw/encode_utf8 decode_utf8/;
use Data::Dumper;

die("usage: cts.pl ontologyName")
    if (@ARGV < 1);

# mode
my $g_mode, $g_submode;

# ontology
my @types_oc, @types_or;
my %map_oc, %map_occ, %map_or;

# timeline
my @types_t;
my %map_t;

# summary
my @types_u, @types_hv;
my %map_smmry;

# Channel Summary
my @types_g;
my %map_g;

# questionaire
my @types_q, @types_qc, @types_ql;
my %map_q, %map_qq, %map_qc, %map_qcc, %map_ql;

my $g_idx;
my $g_sm_idx;
my $g_lc; # モード、サブモード切り替え後のラインカウンタ
my $g_blk;

my $g_n_clmn = 0;  # 制約のカラム数

# 自動生成IDカウンタ
my $g_autoIndex = 0;

MAIN: {
    parseInput();
    outputOntology($ARGV[0], $ARGV[1]);
}

# スタイルシートは縦セル結合無しの前提
sub parseInput {
    my $csv = Text::CSV_XS->new({ binary => 1 });
	my $f_inc = 1;
    local $lc;

	$g_blk = "";
	$g_idx = 0;
	$g_sm_idx = 0;

    #my $lastFields;
    while (my $fields = $csv->getline(*STDIN)) {
		$lc++;
		$g_idx++;

		if ($f_inc != 0) {
			$g_lc++;
		}

		$f_inc = extract(@$fields);
    }
}

# カラムごとの処理
sub extract {
	my $clmn = 0;
	my $idx = 0;
	my $pre = "";
	my $exec = 0;

    foreach $_ (@_) {
		if (($g_submode eq "constraint") && ($clmn < $g_n_clmn)) {
			# 空セルに意味がある場合がある。
		}
		else {
			next unless ($_);
		}

		$g_autoIndex++;

		if (/^\\.*/) {
			#コメントカラム
		}
		else {
			$exec++;

			if (/^[<\]][ORCTUHVGQL](,*)?/) {
				#Mode 先頭カラムでしか出現しないので、本来、カラム毎にチェックは不要
				my ($kw, $id, $label) = split(/[, \s]+/, $_, 3);
				$g_blk = changeMode($kw, $id, $label);
				$g_n_clmn = 0;
			}
			elsif ($g_mode eq "O") {
				# オントロジー
				if ($g_submode eq "restriction") {
					my ($item, $params) = split(/[ \n]+/, $_, 2);
					ontRestriction($g_blk, "#$item", $params);
				}
				elsif ($g_submode eq "constraint") {
					ontConstraint($g_blk, $clmn, $_);
				}
			}
			elsif ($g_mode eq "T") {
				# タイムライン
				my ($id, $params) = split(/[ \n]+/, $_, 2);
				timeline($g_blk, $id, $params);
			}
			elsif ($g_mode eq "Q") {
				# 問診
				unless ($g_submode) {
					$idx = questionnarie($g_blk, $idx, $clmn, $_);
				}
				elsif ($g_submode eq "constraint") {
					questionConstraint($g_blk, $clmn, $_);
				}
				elsif ($g_submode eq "layout") {	
					questionLayout($g_blk, $_);
				}
			}
			elsif ($g_mode eq "U" || $g_mode eq "H" ||$g_mode eq "V") {
				# ユニットサマリ,左右方向時系列サマリ,上下方向時系列サマリ
				# 構成がユニットサマリと同一なので、共用する。
				unitSummary($g_blk, $g_lc-1, $clmn, $_);
			}
			elsif ($g_mode eq "G") {
				# チャネルサマリ
				$pre = channelSummary($pre, $g_blk, $g_lc-1, $clmn, $_);
			}
		}
		$clmn++;
	}

	if ($exec == 0) {
		return 0;
	}

	return 1;
}

#　オントロジー：限定(Restriction)
sub ontRestriction {
    my ($blk, $id, $params) = @_;

    /.*/;
    $params =~ s/^(\w+)//;
    my $val = "$1";

    if ($blk) {
		my %rr_item = (
			"$id" => "$val"
			);

		my $rr = $blk->{'defines'};
		unless ($rr) {
			#  新規作成：Jacksonの都合、１個でも[ ]で囲む。
			$blk->{'defines'} = [ \%rr_item ];
		} else {
			push(@$rr, \%rr_item);
		}
    }
}

# オントロジー：制約(constraint)
my @o_clmn;
my $g_evtValIndex;
sub ontConstraint {
	my ($blk, $clmn, $params) = @_;
	my $items = "";

	# 0行目は変項定義
	if ($g_lc == 0) {
		# 変項は[ ] で囲まれているので、片方を利用して分割
		my @clsname = split(/]/,$params);

		foreach my $cls (@clsname) {
			# 先頭の[を削除し、期間記述しと分割する
			$cls =~ s/^(\s)?\[//;
			$cls =~ s/^(\w+)[:]//;
			my $id = $1;
			my $period = $cls;

			if ($id eq "") {
				$id = $cls;
				$period = "";
			}

			my %elm = (
				'@id' => "$id",
				'index' => "$g_evtValIndex",
				'type' => "$clmn"
				);

			if ($period ne "") {
				$elm{'period'} = "$period";
			}

			$g_evtValIndex++;

			my $evtval = $blk->{"eventVariables"};
			unless ($evtval) {
				$blk->{'eventVariables'} = [ \%elm ];
			}
			else {
				push(@$evtval, \%elm);
			}
		}
	}
	# 1行目は項目名
	elsif ($g_lc == 1) {
		# 変項のtypeをふり分ける：全変項が揃うまでできないので、ここで実施
		my $evtval = $blk->{"eventVariables"};
		my $max_clmn = 0;
		my $already_check = 0;
		# カラム数の最大値を求める
		foreach my $elm (@$evtval) {
			if ($elm->{'type'} =~ /^[(pv)?(sv)?]/) {
				$already_check = 1;
			}

			if ($max_clmn < $elm->{'type'}) {
				$max_clmn = $elm->{'type'};
			}
		}

		if ($g_n_clmn < $max_clmn) {
			$g_n_clmn = $max_clmn;
		}

		if ($already_check eq 0) {
			# 主変項、従属変項の設定を書き込む
			foreach my $elm (@$evtval) {
				if ($elm->{'type'} eq $max_clmn) { # 最右セル中のEventVariableを主変項
					$elm->{'type'} = "pv";

					if ($max_clmn eq 1) { # 1項目しか無い場合
						$elm->{'type'} = "pvsv";
					}
				}
				else {
					$elm->{'type'} = "sv";
				}
			}
		}

		# 項目名配列をクリア
		if ($clmn == 0) {
			@o_clmn = ();
		}

		push(@o_clmn, $params);

		return 0;
	}
	# 以下、値が入る
	else {
		# 項目名を取得
		my $nm = $o_clmn[$clmn];
		my $elm = $map_occ->{$g_idx};

		if ($clmn == 0) {
			my $rightmost = "";

			# 出力時に空項目も出力させるため、全項目に空要素を入れる。
			foreach (@o_clmn) {
				$elm->{$_} = "";
				$rightmost = $_;
			}
			$map_occ->{$g_idx} = $elm;

			# 最左右行
			#$blk->{'leftmostColumn'} = $o_clmn[0]; # 最左行
			#$blk->{'rightmostColumn'} = $rightmost; # 最右行
		}

		$elm->{$nm} = "$params";

		my $df = $blk->{'defines'};
		unless ($df) {
			$blk->{'defines'} = [ \%$elm ];
		} else {
			if ($clmn == 0) {
				push(@$df, \%$elm);
			}
		}
	}

	return $idx;
}

# タイムライン　
sub timeline {
    my ($blk, $id, $params) = @_;

    /.*/;
    if ($blk) {
		#　タイムラインは、スプレッドシート記述とは逆に
		#　条件をキーとなるように格納する。
		my %rr_item = (
			"$params" => "$id"
			);

		my $rr = $blk->{'defines'};
		unless ($rr) {
			#  新規作成：Jacksonの都合、１個でも[ ]で囲む。
			$blk->{'defines'} = [ \%rr_item ];
		} else {
			push(@$rr, \%rr_item);
		}
    }
}

# ユニットサマリ
sub unitSummary {
    my ($blk, $line, $column, $params) = @_;

    /.*/;
	# 改行を廃し
	$params =~ s/\n//;

	# 先頭要素
	$params =~ s/^(\w+)//;
    my $rule = "$1";

	#先頭のホワイトスペース削除
	$params =~ s/^(\s+)//;

	# 格納場所を確保
	$idx = $g_sm_idx;
	$us_item = $map_smmry{$idx};
	$g_sm_idx++;

    if ($blk) {
		
		# 改行を廃し、'|'で切り分ける
		my @prm_list = split(/\|/, $params);

		$us_item = {
			"line" => "$line",
			"column" => "$column",
			"rule" => "$rule"
		};

		# 各パラメータ
		foreach my $str (@prm_list) {
			$tp = is_strFormat($str);
			if ($tp eq "label") {
				parseLabel($us_item, $str);
			}
			elsif ($tp eq "format") {
				parseLabelLang($us_item, $str, "format");
				#$us_item->{'format'} = "$str";
			}
			elsif ($tp eq "order") {
				$us_item->{'order'} = "$str";
			}
			elsif ($tp eq "align") {
				$us_item->{'align'} = "$str";
			}
			elsif ($tp eq "width") {
				$us_item->{'width'} = "$str";
			}
			elsif ($tp eq "color") {
				$str =~ s/(\s)//;
				$us_item->{'color'} = "$str";
			}
		}

		$map_smmry{$idx} = $us_item;

		my $rr = $blk->{'defines'};
		unless ($rr) {
			#  新規作成：Jacksonの都合、１個でも[ ]で囲む。
			$blk->{'defines'} = [ $us_item ];
		} else {
			push(@$rr, $us_item);
		}
    }
}

# サマリパラメータの解析
# 中身で判別するので抜けがあるかも
sub is_strFormat {
    my ($str) = @_;

	# ; : があればラベル
	if ($str =~ /^.+[:;]/) {
		return "label"
	}

	# [ ]があればフォーマット文字列
	if ($str =~ /\[(.+)\]/) {
		return "format";
	}

    # sum|ave|pow|ini|fin|list|card
	my @rsvwd = ("sum","ave","pow","ini","fin","list","card");
	foreach  my $ky (@rsvwd) {
		if ($str =~ /^$ky\s?$/) {
			return "format";
		}
	}

    # red|blue|yellow|green|black|white
	my @colwd = ("red","blue","yellow","green","black","white");
	foreach  my $ky (@colwd) {
		if ($str =~ /^$ky\s?$/) {
			return "color";
		}
	}

	# align
	if ($str =~ /^[LT]\s?$/) {
		return "align";
	}
	# align
	if ($str =~ /^[LT][EP]?\s?$/) {
		return "align";
	}
	if ($str =~ /^[EP][LT]?\s?$/) {
		return "align";
	}

	# order
	if ($str =~ /^A\s?$/) {
		return "order";
	}

	# width
	if ($str =~ /^[0-9]+%?(cm)?\s?$/) {
		return "width";
	}

	return "label";
}

# チャネルサマリ
sub channelSummary {
    my ($preidx, $blk, $line, $column, $params) = @_;

    /.*/;
	# 改行を廃し
	$params =~ s/\n//;

	#先頭のホワイトスペース削除
	$params =~ s/^(\s+)//;
	$params =~ s/(\s+)$//;

	# constraint
	if ($params =~ /^bg:.*/) {
		if ($preidx == "") {
			return $preidx;
		}

		$us_item = $map_smmry{$preidx};
		#$us_item->{'constraint'} = $params;
		#
		my $cnst = $us_item->{'constraint'};
		unless ($cnst) {
			$us_item->{'constraint'} = [ $params ];
		}
		else {
			push(@$cnst, $params);
		}
        #

		return $preidx;
	}

	# 先頭要素
	$params =~ s/^(\S+)//;
    my $id = "$1";

	#先頭のホワイトスペース削除
	$params =~ s/^(\s+)//;

	# 格納場所を確保
	$idx = $g_sm_idx;
	$us_item = $map_smmry{$idx};
	$g_sm_idx++;

    if ($blk) {
		$us_item = {
			"line" => "$line",
			"column" => "$column"
		};

		parseLabelLang($us_item, $id, "label");
		parseLabelLang($us_item, $params, "format");

		$map_smmry{$idx} = $us_item;

		my $rr = $blk->{'defines'};
		unless ($rr) {
			#  新規作成：Jacksonの都合、１個でも[ ]で囲む。
			$blk->{'defines'} = [ $us_item ];
		} else {
			push(@$rr, $us_item);
		}
    }

	return $idx;
}

# 問診
sub questionnarie {
	my ($blk, $idx, $clmn, $params) = @_;
	my $items = "";

	if ($idx != 0) {
		$items = $map_qq{$idx};
	}

	# page pagelayout
	if ($clmn == 0) {
		my ($page, $playout, $qlayout) = split(/[ \s]/, $params, 3);

	    # 0カラム
		$idx = $g_idx;
		$items = $map_qq{$idx};
		$items = {
			"page" => "$page"
		};

		if ($playout) {
			$items->{'pageLayout'} = $playout;
		}

		if ($qlayout) {
			$items->{'questionLayout'} = $qlayout;
		}

		my $df = $blk->{'defines'};
		unless ($df) {
			$blk->{'defines'} = [ \%$items ];
		} else {
			push(@$df, \%$items);
		}

		$map_qq{$idx} = $items;
	}
	elsif ($clmn == 1) {
		# auestions
		my @pages = split(/ /, $params);

		# クラス名先頭に#を付加する
		for (my $i=0; $i < @pages; $i++) {
			$pages[$i] = "#$pages[$i]";
		}

		if (@pages) {
			$items->{'questions'} = \@pages;
		}
	}
	elsif ($clmn == 2) {
		# next
		my @pages = split(/ /, $params);
		if (@pages) {
			$items->{'next'} = \@pages;
		}
	}

	return $idx;
}

# 問診　レイアウト
sub questionLayout {
	my ($blk, $params) = @_;

	if ($blk) {
		my $elm = {
			"body" => "$params"
		};

		my $df = $blk->{'defines'};
		unless ($df) {
			$blk->{'defines'} = [ \%$elm ];
		} else {
			push(@$df, \%$elm);
		}
	}
}

# 問診：制約 constraint
# 格納先以外はオントロジー制約と同じなので、ひと段落ついたら整理する。
my @g_clmn;
sub questionConstraint {
	my ($blk, $clmn, $params) = @_;
	my $items = "";

	# 0行目は変項定義
	if ($g_lc == 0) {
		# 変項は[ ] で囲まれているので、片方を利用して分割
		my @clsname = split(/]/,$params);

		foreach my $cls (@clsname) {
			# 先頭の[を削除し、期間記述しと分割する
			$cls =~ s/^(\s)?\[//;
			$cls =~ s/^(\w+)[:]//;
			my $id = $1;
			my $period = $cls;

			$id =~ s/^(\s)//;

			if ($id eq "") {
				$id = $cls;
				$period = "";
			}

			my %elm = (
				'@id' => "$id",
				'index' => "$g_evtValIndex",
				'type' => "$clmn"
				);

			if ($period ne "") {
				$elm{'period'} = "$period";
			}

			$g_evtValIndex++;

			my $evtval = $blk->{"eventVariables"};
			unless ($evtval) {
				$blk->{'eventVariables'} = [ \%elm ];
			}
			else {
				push(@$evtval, \%elm);
			}
		}
	}
	# 1行目は項目名
	elsif ($g_lc == 1) {
		my $already_check = 0;

		# 変項のtypeをふり分ける：全変項が揃うまでできないので、ここで実施
		my $evtval = $blk->{"eventVariables"};
		my $max_clmn = 0;
		# カラム数の最大値を求める
		foreach my $elm (@$evtval) {
			if ($elm->{'type'} =~ /^[(pv)?(sv)?]/) {
				$already_check = 1;
			}

			if ($max_clmn < $elm->{'type'}) {
				$max_clmn = $elm->{'type'};
			}
		}

		if ($g_n_clmn < $max_clmn) {
			$g_n_clmn = $max_clmn;
		}

		if ($already_check eq 0) {
			# 主変項、従属変項の設定を書き込む
			foreach my $elm (@$evtval) {
				if ($elm->{'type'} eq $max_clmn) { # 最右のEventVariableを主変項
					$elm->{'type'} = "pv";

					if ($max_clmn eq 1) { # 1項目しか無い場合
						$elm->{'type'} = "pvsv";
					}
				}
				else {
					$elm->{'type'} = "sv";
				}
			}
		}

		# 項目名配列をクリア
		if ($clmn == 0) {
			@g_clmn = ();
		}

		push(@g_clmn, $params);
		return 0;
	}
	# 以下、値が入る
	else {
		# 項目名を取得
		my $nm = $g_clmn[$clmn];
		my $elm = $map_qcc->{$g_idx};

		if ($clmn == 0) {
			my $rightmost = "";

			# 出力時に空項目も出力させるため、全項目に空要素を入れる。
			foreach (@g_clmn) {
				$elm->{$_} = "";
				$rightmost = $_;
			}
			$map_qcc->{$g_idx} = $elm;

			# 最左右行
			#$blk->{'leftmostColumn'} = $g_clmn[0]; # 最左行
			#$blk->{'rightmostColumn'} = $rightmost; # 最右行
		}

		$elm->{$nm} = "$params";

		my $df = $blk->{'defines'};
		unless ($df) {
			$blk->{'defines'} = [ \%$elm ];
		} else {
			if ($clmn == 0) {
				push(@$df, \%$elm);
			}
		}
	}
}


# mode: 行頭]で始まる
#  ]O オントロジー定義
#  ]Q 問診
#  ]T タイムライン
#  ]U １日分サマリ
#  ]H 複数日サマリ
#  ]G チャネルサマリ
#
# subMode: 現在のmodeに紐つく
#  ]R 限定：Restriction
#  ]C 制約：Constraint
#  ]L レイアウト
sub changeMode {
    my ($kws, $id, $params) = @_;

	my $kw = $kws;
	$kws =~ s/^([<\]][ORCTUHVGQL])//;
	$kw = $1;

	# 旧仕様(先頭'<')対策
	$kw =~ s/^</\]/;

	# mode
	if ($kw eq "]O") {
		# オントロジー
		$g_mode = "O";
        $g_submode = "";
	}
    elsif ($kw eq "]Q") {
		# 問診
		$g_mode = "Q";
        $g_submode = "";
	}
	elsif ($kw eq ']T') {
		# タイムライン
		$g_mode = "T";
        $g_submode = "";
	}
	elsif ($kw eq ']U') {
		# ユニットサマリ
		$g_mode = "U";
        $g_submode = "";
	}
	elsif ($kw eq ']H') {
		# 時系列サマリ 時間の向き左➡右
		$g_mode = "H";
        $g_submode = "";
	}
	elsif ($kw eq ']V') {
		# 時系列サマリ 時間の向き右➡左
		$g_mode = "V";
        $g_submode = "";
	}
	elsif ($kw eq ']G') {
		#  チャネルサマリ
		$g_mode = "G";
        $g_submode = "";
	}
    # submode
    elsif ($kw eq "]R") {
		$g_submode = 'restriction';
	}
    elsif ($kw eq "]C") {
		$g_submode = 'constraint';
	}
    elsif ($kw eq "]L") {
		$g_submode = 'layout';
	}
    # unknown
    else {
		$g_mode = "";
        $g_submode = "";
		return "";
	}

	$g_lc = 0;
	$g_evtValIndex = 0; # eventVariable のインデクスは0から始める

	my $typ = "";
	my $map = "";

	if ($g_mode eq "O") {
		if ($g_submode eq 'restriction') {
			$typ = \@types_or;
			$map = \%map_or;
		}
		elsif ($g_submode eq 'constraint') {
			$typ = \@types_oc;
			$map = \%map_oc;
		}
	}
	elsif ($g_mode eq "T") {
		$typ = \@types_t;
		$map = \%map_t;
	}
	elsif ($g_mode eq "U") {
		$typ = \@types_u;
		$map = \%map_smmry;
	}
	elsif ($g_mode eq "H" || $g_mode eq "V") {
		$typ = \@types_hv;
		$map = \%map_smmry;
	}
	elsif ($g_mode eq "G") {
		$typ = \@types_g;
		$map = \%map_g;
	}
	elsif ($g_mode eq "Q") {
		unless ($g_submode) {
			$typ = \@types_q;
			$map = \%map_q;
		}
		elsif ($g_submode eq 'constraint') {
			$typ = \@types_qc;
			$map = \%map_qc;
		}
		elsif ($g_submode eq 'layout') {
			$typ = \@types_ql;
			$map = \%map_ql;
		}
	}

	# ID 無しの場合、自動採番IDを付与する。
	unless ($id) {
		$id = "AutoID_" . $g_autoIndex;
		$g_autoIndex++;
	}
	
	# 重複チェック
	my $blk = $map->{"$id"};
	if ($blk) {
		print STDERR "Error: Property `$id' was already defined " . "at line $lc\n";
		return "";
	}

	# 重複無し、すなわち新規
	$blk = {
		'@id' => "$id"
	};

	# ヘッダパラメータの取り込み
	if ($params) {
		if ($g_submode eq 'C') {
			# [? ID path  label
			my ($path, $label) = split(/[ \s]+/, $params, 2);

			if ($path) {
				$blk->{'path'} = $path;
			}

			if ($label) {
				parseLabel($blk, $label);
			}
		}
		elsif ($g_mode eq 'T') {
			# [? ID S/R Period label
			my ($subject, $label) = split(/[ \s]+/, $params, 2);

			if ($subject) {
				$blk->{'subject'} = $subject;
			}

			if ($label) {
				parseLabel($blk, $label);
			}
		}	
		elsif ($g_mode eq 'U' || $g_mode eq 'H' || $g_mode eq 'V' || $g_mode eq 'G') {
			# [? ID S/R Period label
			my ($subject, $period, $label) = split(/[ \s]+/, $params, 3);

			if ($subject) {
				$blk->{'subject'} = $subject;
			}

			if ($period) {
				$blk->{'period'} = $period;
			}

			if ($label) {
				parseLabel($blk, $label);
			}
		}	
		else {
			# <? ID (label)
			if ($params) {
				parseLabel($blk, $params);
			}
		}
	}

	$map->{"$id"} = $blk;
	push(@$typ, $blk);

	return $blk;
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
		if ($la[$i]) {
			parseLabelLang($type, $la[$i], $ky);
		}

		$i++;
	}
}

sub parseLabelLang {
    my ($type, $label, $propName) = @_;

    my %ll;

	# local毎に分解 (local:string;...)[]
    my @l = split(/;/, $label, 3);

    foreach $lcl (@l) {

		$lcl =~ s/\n//;

		# localと本文に分解
		my @elm = split(/:/, $lcl, 2);

		# localが無い
		if (@elm == 1) {
			$ll{''} = $elm[0] if ($elm[0]);
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

sub outputOntology {
    my ($ontologyName, $prefix) = @_;

	my $context = "http://PUBLIC/ontologies/menuContext.jsonld";
    my $json = JSON->new->pretty->canonical;
	my $idname = "";
	my $label;

    die("Error: failed to open file `$ontologyName" . "_stylesheet" . ".jsonld': $!\n")
	unless (open(F, ">$ontologyName" . "_stylesheet" . ".jsonld"));

	my %ont = "";
	if (@types_or) {
		$ont->{'restriction'} = \@types_or;
	}
	if (@types_oc) {
		$ont->{'constraint'} = \@types_oc;
	}

	my $qst = "";
	if (@types_q) {
		$qst = {
			'questionnaire' => $types_q[0]
		};

		if (@types_ql) {
			$qst->{'layout'} = \@types_ql;
		}

		if (@types_qc) {
			$qst->{'constraint'} = \@types_qc;
		}
	}
	
	my $tl = "";
	if (@types_t) {
		$tl = {
			'timeline' => \@types_t
		};
	}

	my %sm = "";
	if (@types_u) {
		$sm->{'unit'} = \@types_u;
	}
	if (@types_hv) {
		$sm->{'chronological'} = \@types_hv;
	}
	if (@types_g) {
		$sm->{'channel'} = \@types_g;
	}

	my $oj = {
		'@context' => $context
	};

	if ($ont) {
		$oj->{'ontology'} = $ont;
	}
	if ($qst) {
		$oj->{'questionnaire'} = $qst;
	}
	if ($tl) {
		$oj->{'timeline'} = $tl;
	}
	if ($sm) {
		$oj->{'summary'} = $sm;
	}

	# スタイルシートJSON-LD
    print F encode_utf8($json->encode($oj));
    close(F);

	
	# 分割出力 -------
	my $count;
	my $i;
	
	#constraint 出力
	$count =  @types_oc;
	for ($i = 0; $i < $count; $i++) {
		open(F, ">$ontologyName" . "_stylesheet_constraint" . $i . ".jsonld");
		my $obj = {
			'@context' => $context
		};
		$obj->{'constraint'} = $types_oc[$i];
		print F encode_utf8($json->encode($obj));
		close(F);
	}

	#restriction 出力
	$count =  @types_or;
	for ($i = 0; $i < $count; $i++) {
		open(F, ">$ontologyName" . "_stylesheet_restriction" . $i . ".jsonld");
		my $obj = {
			'@context' => $context
		};
		$obj->{'restriction'} = $types_or[$i];
		print F encode_utf8($json->encode($obj));
		close(F);
	}

	#timeline 出力
	$count =  @types_t;
	for ($i = 0; $i < $count; $i++) {
		open(F, ">$ontologyName" . "_stylesheet_timeline" . $i . ".jsonld");
		my $obj = {
			'@context' => $context
		};
		$obj->{'timeline'} = $types_t[$i];
		print F encode_utf8($json->encode($obj));
		close(F);
	}

	#unit summary 出力
	$count =  @types_u;
	for ($i = 0; $i < $count; $i++) {
		open(F, ">$ontologyName" . "_stylesheet_unitsummary" . $i . ".jsonld");
		my $obj = {
			'@context' => $context
		};
		my $sm = {
			'channel' => $types_u[$i]
		};
		$obj->{'summary'} = $sm;
		print F encode_utf8($json->encode($obj));
		close(F);
	}

	#chronological summary 出力
	$count =  @types_hv;
	for ($i = 0; $i < $count; $i++) {
		open(F, ">$ontologyName" . "_stylesheet_chronologicalsummary" . $i . ".jsonld");
		my $obj = {
			'@context' => $context
		};
		my $sm = {
			'channel' => $types_hv[$i]
		};
		$obj->{'summary'} = $sm;
		print F encode_utf8($json->encode($obj));
		close(F);
	}

	#channel summary 出力
	$count =  @types_g;
	for ($i = 0; $i < $count; $i++) {
		open(F, ">$ontologyName" . "_stylesheet_channelsummary" . $i . ".jsonld");
		my $obj = {
			'@context' => $context
		};
		my $sm = {
			'channel' => $types_g[$i]
		};
		$obj->{'summary'} = $sm;
		print F encode_utf8($json->encode($obj));
		close(F);
	}

	#questionnaire 出力
	if ($qst) {
		open(F, ">$ontologyName" . "_stylesheet_questionnaire" . ".jsonld");
		my $obj = {
			'@context' => $context
		};
		$obj->{'questionnaire'} = $qst;
		print F encode_utf8($json->encode($obj));
		close(F);
	}
}


# end of file
