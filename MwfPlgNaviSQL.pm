#------------------------------------------------------------------------------
#    mwForum - Web-based discussion forum
#    Copyright (c) 1999-2008 Markus Wichitill
#
#    MwfPlgNaviSQL.pm - SQL Generation
#    Copyright (c) 2010 Tobias Jaeggi, modified for SQL 2010 by Murray Colpman
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

package MwfPlgNaviSQL;
use strict;
use warnings;
our $VERSION = "2.22.1";

use Net::FTP;

sub create {
  my %params = @_;
  my $m = $params{m};
  my $cfg = $m->{cfg};
  my @words = @{$params{words}};
  my $ftp = $params{ftp};
  my @lcs = @{$params{languages}};

	# Clean up
  `rm -f $cfg->{EE}{tmpDir}/*.sql`;

	# Open file handles to avoid iterating X times through @words
  my $file;
  open($file, '>::utf8', "$cfg->{EE}{tmpDir}/NaviData.sql") or $m->error("Could not open file! ($! for $cfg->{EE}{tmpDir}/NaviData.sql)");
  $file or $m->error("could not open file");

  print $file <<EOSQL;
-- IMPORTANT notices about this SQL file
-- Eana Eltu SQL data by Tobias Jaeggi (Tuiq, tuiq\@clonk2c.ch), Richard Littauer (Taronyu, richard\@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ).
-- The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .

-- localized table.
CREATE TABLE IF NOT EXISTS `localizedWords` (`id` char(40) NOT NULL,`languageCode` char(5) NOT NULL,`localized` text NULL,`partOfSpeech` varchar(100) NULL, UNIQUE KEY `idlc` (`id`,`languageCode`)) DEFAULT CHARSET=utf8;
-- meta table.
CREATE TABLE IF NOT EXISTS `metaWords` (`id` char(40) NOT NULL AUTO_INCREMENT,`navi` varchar(100) NOT NULL,`ipa` varchar(100) NOT NULL,`infixes` varchar(100) NULL,`partOfSpeech` varchar(100) NOT NULL,PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8;
-- TRUNCATE ACTION!
TRUNCATE TABLE `metaWords`;
TRUNCATE TABLE `localizedWords`;
-- INSERT MASSACRE
EOSQL

	# Iterate through @words
  for my $word (@words) {
    print $file "INSERT INTO `metaWords` (`id`,`navi`,`ipa`,`infixes`,`partOfSpeech`) VALUES ('", $word->{id}, "',", $m->{dbh}->quote($word->{nav}), ",", $m->{dbh}->quote($word->{ipa}), ",", $m->{dbh}->quote($word->{svnav}), ",", $m->{dbh}->quote($word->{type}), ");";
		# And now for each language...
		for my $lc (@lcs) {
			next if !$word->{$lc};
      my $type = $word->{"type$lc"} ? $word->{"type$lc"} : $word->{type};
      print $file "INSERT INTO `localizedWords` (`id`,`languageCode`,`localized`,`partOfSpeech`) VALUES ('", $word->{id}, "','", $lc, "',", $m->{dbh}->quote($word->{$lc}), ",", $m->{dbh}->quote($type), ");";
		}
		# We show mercy to poor editors.
		print $file "\n";
	}

  close $file;
  
	# FTP
  $ftp->delete("NaviData.sql");
  $ftp->put("$cfg->{EE}{tmpDir}/NaviData.sql", "NaviData.sql") or $m->error("could not ftp: $!");
}

#-----------------------------------------------------------------------------
1;

