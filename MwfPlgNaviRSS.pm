#------------------------------------------------------------------------------
#    mwForum - Web-based discussion forum
#    Copyright (c) 1999-2008 Markus Wichitill
#
#    MwfPlgNaviRSS.pm - RSS Generation
#    Copyright (c) 2010 Tobias Jaeggi, modified for RSS 2010 by Murray Colpman
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

package MwfPlgNaviRSS;
use strict;
use warnings;
our $VERSION = "2.22.1";

use Net::FTP;
use Time::Format;

sub create {
  my %params = @_;
  my $m = $params{m};
  my $cfg = $m->{cfg};
  my @words = @{$params{words}};
  my @sorted = sort {$b->{editTime} <=> $a->{editTime}} @words;
  my $ftp = $params{ftp};
  my @lcs = @{$params{languages}};
  my @rssmessages = (1,10,25,50);

	# Clean up
  `rm -f $cfg->{EE}{tmpDir}/*.rss`;

	# Open file handles to avoid iterating X times through @words
  my %files = ();
  for my $number (@rssmessages){
  open($files{$number}, '>::utf8', "$cfg->{EE}{tmpDir}/NaviUpdates_${number}.rss") or $m->error("Could not open file! ($! for $cfg->{EE}{tmpDir}/NaviUpdates_${number}.rss)");
  $files{$number} or $m->error("could not open file");


  print {$files{$number}} <<EORSS;
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Na'vi dictionary updates</title>
    <link>http://forum.learnnavi.org/intermediate/my-dictionary/</link>
    <description>List of Na'vi words recently modified.</description>
    <language>en-gb</language>
    <pubDate>$time{"Day, dd Mon yyyy hh:mm:ss +0100", ${sorted[0]}->{"editTime"}}</pubDate>
    <lastBuildDate>$time{"Day, dd Mon yyyy hh:mm:ss +0100"}</lastBuildDate>
    <docs>http://www.rssboard.org/rss-specification</docs>
    <generator>RSS generator for Eana Eltu 1.0</generator>
    <copyright>Eana Eltu RSS data by Tobias Jaeggi (Tuiq, tuiq\@clonk2c.ch), Richard Littauer (Taronyu, richard\@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ). The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .</copyright>
EORSS
  }

	# Iterate through @words
        my $done = 0;
        for my $word (@sorted) {
          for my $number (@rssmessages){
          if($done < $number){
          print {$files{$number}} "<item>\n<title><![CDATA[$word->{nav}]]></title>\n<pubDate>$time{\"Day, dd Mon yyyy hh:mm:ss +0100\", $word->{editTime}}</pubDate>\n<description><![CDATA[Na'vi: $word->{nav}<br />IPA: $word->{ipa}<br />Part of speech: $word->{type}<br />";
		# And now for each language...
		for my $lc (@lcs) {
			next if !$word->{$lc};
         print {$files{$number}} "$lc: $word->{$lc}<br />";
		}
		# We show mercy to poor editors.
		print {$files{$number}} "]]></description></item>\n";
          }
          }
          $done++;
	}
        for my $number (@rssmessages) {
        print {$files{$number}} "</channel>\n</rss>\n";

  close $files{$number};
  
	# FTP
  $ftp->delete("NaviUpdates_$number.rss");
  $ftp->put("$cfg->{EE}{tmpDir}/NaviUpdates_$number.rss", "NaviUpdates_$number.rss") or $m->error("could not ftp: $!");
}
}

#-----------------------------------------------------------------------------
1;

