#!/usr/bin/perl
# vrrteptest.pl, part of Eana Eltu by Tobias Jaeggi (Tuiq, tuiq at clonk2c dot ch), Richard Littauer (Taronyu, richard@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ).
# The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .

use strict;
use warnings;
use Data::Dumper;
use YellNavi;
# We cheat.
use EEConfig;

# We pick a random key. The first should always be the main key, so.
my $key;
{
	open(my $FH, '.keys');
	$key = (<$FH>)[0];
	close $FH;
}

my $yn = YellNavi->new(file => $EEConfig::cfg->{serverfile}, key => $key);

if (!$yn->connect) {
	die "Could not connect.\n";
}

# We are cheating.
$yn->askPeristentMode;
print "Starting test modes.\n";
$yn->askLookup('eltu', ['nav'], 0);
print "Lookup done.\n";
$yn->askNum('1337');
print "Num done.\n";
$yn->askTranslation('aytseng');
print "Translation done.\n";
print "Fetching all data; this could take a while.\n";
$yn->askAllData();
print "All data done.\n";
print "Done.\n";