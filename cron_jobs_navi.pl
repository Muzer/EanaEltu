#!/usr/bin/perl
#------------------------------------------------------------------------------
#    mwForum - Web-based discussion forum
#    Copyright (c) 1999-2008 Markus Wichitill
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
no warnings qw(uninitialized redefine);

# Imports
use Getopt::Std ();
use MwfMain;
use YellNavi;
use Net::FTP;

#------------------------------------------------------------------------------

# Get arguments
my %opts = ();
Getopt::Std::getopts('f:', \%opts);
my $forumId = $opts{f};

# Init
my ($m, $cfg, $lng) = MwfMain->newShell(forumId => $forumId);

#------------------------------------------------------------------------------
# Get all our words
my $yn = YellNavi->new(file => $cfg->{EE}{demonFile}, key => $cfg->{EE}{demonKey});
if (!$yn->connect) {
	die('Could not connect to demon.');
}

$yn->askRefresh;
my $languages = $yn->askLanguages;
my @languages = keys %$languages;

my $data = $yn->askAllData;
if (!$data || $@ || $!) {
	die("Error asking demon for all data.");
}

# Open FTP.
my $ftp = Net::FTP->new($cfg->{EE}{ftp}{server}, Timeout => 30, Passive => 1) or $m->error("could not connect to ftp");
$ftp->login($cfg->{EE}{ftp}{user}, $cfg->{EE}{ftp}{password}) or $m->error("could not ftp login");
$ftp->binary() or $m->error("could not binary");
$ftp->cwd($cfg->{EE}{ftp}{dir}) or $m->error("could not cwd");

$m->callPlugin("${_}::create", words => $data, ftp => $ftp, languages => \@languages) for @{$cfg->{EE}{addons}};

$m->logAction(1, 'navicj', 'exec');