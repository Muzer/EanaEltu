#!/usr/bin/perl
#------------------------------------------------------------------------------
#    mwForum - Web-based discussion forum
#    Copyright (c) 1999-2009 Markus Wichitill
#
#    util_dumpnavisql.pl
#    Copyright (c) 2010 Tobias Jaeggi
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#------------------------------------------------------------------------------

use strict;
use warnings;
no warnings qw(uninitialized once);

# Imports
use MwfMain;
use Data::Dumper;

# Init
my ($m, $cfg, $lng) = MwfMain->newShell();

# We'll save the data in this field.
my @metaWords;
my @localizedWords;

# Get the available types.
my @types = map { $_->[0] } @{$m->fetchAllArray('SELECT DISTINCT(type) FROM dictWordMeta')};
# and blocks
my @blocks = map { $_->[0] } @{$m->fetchAllArray('SELECT DISTINCT(block) FROM dictWordMeta')};

# Now, for each block
# We only dump up to five words per block and type.
for my $block (@blocks) {
	# Get one of these words.
	for my $type (@types) {
		my $results = $m->fetchAllHash('SELECT * FROM dictWordMeta WHERE block = ? && type = ? LIMIT 5', $block, $type);
		next if !$results;
		for my $result (@$results) {
			push @metaWords, $result;
			
			my $localizedResults = $m->fetchAllHash('SELECT * FROM dictWordLoc WHERE id = ?', $result->{id});
			push @localizedWords, $_ for (@$localizedResults);
		}
	}
}

# Full data: Infixes (and other stuff, but we call it 'infixes'.)
#~ "SELECT * FROM dictWordMeta WHERE block = 3 || block = 4 || type = 'pcw' || type = 'pderives'"
my $infixes = $m->fetchAllHash("
	SELECT * 
	FROM dictWordMeta 
	WHERE (
		(`type` = 'infix' || `type` = 'infixcw') && block = 2)
		|| 
		(block = 3 || block = 4 || type = 'pcw' || type = 'pderives')
		||
		(id = 294 || id = 511 || id = 556)
	");

for my $infix (@$infixes) {
	push @metaWords, $infix;
	my $localizedInfixes = $m->fetchAllHash('SELECT * FROM dictWordLoc WHERE id = ?', $infix->{id});
	push @localizedWords, $_ for (@$localizedInfixes);
}

# Throw out duplicates
{
	my %metafound;
	@metaWords = grep { !$metafound{$_->{id}}++ } @metaWords;
	my %localizedfound;
	@localizedWords = grep { !$localizedfound{$_->{id}.$_->{lc}}++ } @localizedWords;
}

print "Got ", scalar @metaWords, " Metawords and ", scalar @localizedWords, " localized words.\n";
# Now we create SQL out of it. More or less.

open my $FH, '>', 'data.sql';
binmode $FH, ':utf8';

print $FH <<EOD;
-- data.sql, part of Eana Eltu by Tobias Jaeggi (Tuiq, tuiq at clonk2c dot ch), Richard Littauer (Taronyu, richard\@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ).
-- The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .
-- This SQL does not contain the whole database but is enough to keep coders running. It's about 1/10 of the complete database.

CREATE TABLE IF NOT EXISTS `dictWordLoc`(`id` int(11) NOT NULL,`arg1` text,`arg2` text,`arg3` text,`arg4` text,`arg5` text,`arg6` text,`arg7` text,`arg8` text,`arg9` text,`arg10` text,`odd` text,`lc` char(5) character set latin1 NOT NULL,`editTime` int(11) NOT NULL,UNIQUE KEY `id` (`id`,`lc`)) ENGINE=MyISAM DEFAULT CHARSET=utf8;
CREATE TABLE IF NOT EXISTS `dictWordMeta` (`id` int(11) NOT NULL auto_increment,`type` char(50) NOT NULL,`arg1` text NOT NULL,`arg2` text NOT NULL,`arg3` text NOT NULL,`arg4` text NOT NULL,`arg5` text NOT NULL,`arg6` text NOT NULL,`arg7` text NOT NULL,`arg8` text NOT NULL,`arg9` text NOT NULL,`arg10` text NOT NULL,`odd` text NOT NULL,`block` tinyint(4) NOT NULL,`editTime` int(11) NOT NULL,PRIMARY KEY  (`id`)) ENGINE=MyISAM  DEFAULT CHARSET=utf8;

TRUNCATE TABLE `dictWordMeta`; 
TRUNCATE TABLE `dictWordLoc`;

EOD

for my $word (@metaWords) {
	print $FH "INSERT INTO `dictWordMeta` SET ";
	# Magic! Voodoo! Call it what you want.
	print $FH join(',', map { "`$_`=" . $m->{dbh}->quote($word->{$_}) } keys %$word);
	print $FH ";";
}

# Ctrl-D
for my $word (@localizedWords) {
	print $FH "INSERT INTO `dictWordLoc` SET ";
	# Magic! Voodoo! Call it what you want.
	print $FH join(',', map { "`$_`=" . $m->{dbh}->quote($word->{$_}) } keys %$word);
	print $FH ";";
}

close $FH;
print "Done.\n";
$m->finish();