#! /usr/bin/perl
use strict;
use Test::More tests => 1;
use IPC::Open2;
use POSIX ':sys_wait_h';
use File::Temp qw/tempdir/;
use JSON::Parse 'json_file_to_perl';

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

ok(1, "*** empty stylesheet ***");
{
	run_command('cts.pl', <<~'EOD', $dir, 'plrTest0');
  "]O Family
  ja:家族;Family",\オントロジー,,,
  "NuclearFamily
  ja:核家族;nuclear family",child ja:子;child,Person,,
  EOD
	my $p = json_file_to_perl("$dir/plrTest0_stylesheet.jsonld");
	is_deeply($p, {'@context' => 'http://PUBLIC/ontologies/menuContext.jsonld'});
}

ok(1, "*** non-empty stylesheet ***");
{
	run_command('cts.pl', <<~'EOD', $dir, 'plrTest1');
  ]T NoVital S ja:バイタルなし;No Vital,,,,
  VitalSign N,,,,
  EOD
	my $p = json_file_to_perl("$dir/plrTest1_stylesheet.jsonld");
	is($p->{'timeline'}->{'timeline'}->[0]->{'@id'}, 'NoVital');
}

ok(1, "*** class name with hyphen ***");
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
						[sort ('#child', '#Nuclear-Family')]);
}
