#------------------------------------------------------------------------------
#    mwForum - Web-based discussion forum
#    Copyright (c) 1999-2008 Markus Wichitill
#
#    MwfPlgNaviJM.pm - JMemorize Generation
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

package MwfPlgNaviJM;
use strict;
use warnings;
our $VERSION = "2.19.2";

use Net::FTP;

sub create {
	my %params = @_;
	my $m = $params{m};
	my $cfg = $m->{cfg};
	my @words = @{$params{words}};
	my $ftp = $params{ftp};
	my @lcs = @{$params{languages}};
	
	# Clean up
	`rm -f *.jm`;
	
	# Open file handles to avoid iterating X times through @words
	my %files = ();
	for my $lc (@lcs) {
		my $adding = $lc eq 'eng' ? '' : "_$lc";
		open($files{$lc}, '>::utf8', "$cfg->{EE}{tmpDir}/$cfg->{EE}{addonBasename}$adding.jm") or $m->error("Could not open file for $lc! ($! for $cfg->{EE}{tmpDir}/$cfg->{EE}{addonBasename}$adding.jm)");
		$files{$lc} or $m->error("could not open file $lc");
		print {$files{$lc}} "Na'vi\t$lc\tPoS\n";
	}
	
	# Iterate through @words
	for my $word (@words) {
		# For each language...
		for my $lc (@lcs) {
			$files{$lc} && defined $files{$lc} or $m->error("filehandle for $lc closed!");
			next if !$word->{$lc};
			my $type = $word->{"type$lc"} ? $word->{"type$lc"} : $word->{type};
			print {$files{$lc}} $word->{nav}, "\t", $word->{$lc}, "\t", $type, "\n";
		}
	}
	
	for my $lc (@lcs) {
		close $files{$lc};
		# FTP
		my $adding = $lc eq 'eng' ? '' : "_$lc";
		$ftp->delete("$cfg->{EE}{addonBasename}$adding.jm");
		$ftp->put("$cfg->{EE}{tmpDir}/$cfg->{EE}{addonBasename}$adding.jm", "$cfg->{EE}{addonBasename}$adding.jm") or $m->error("could not ftp: $!");
	}
}

#-----------------------------------------------------------------------------
1;
