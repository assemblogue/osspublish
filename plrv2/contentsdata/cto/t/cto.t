#! /usr/bin/perl
use strict;
use IPC::Open2;
use POSIX ':sys_wait_h';
use File::Temp qw/tempdir/;
use JSON::Parse 'json_file_to_perl';
use Test::More tests => 4;

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

done_testing();
