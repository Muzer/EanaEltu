#!/usr/bin/perl
#------------------------------------------------------------------------------
#    mwForum - Web-based discussion forum
#    Copyright (c) 1999-2009 Markus Wichitill
#
#    do_magic_navi_image.pl
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
no warnings qw(uninitialized redefine);
#~ use CGI::Carp qw(fatalsToBrowser);
use Time::Format;

# Imports
use MwfMain;
use GD;
use YellNavi;

# Init
my ($m, $cfg, $lng, $user, $userId) = MwfMain->new(@_);

my $db = YellNavi->new(file => $cfg->{EE}{demonFile}, key => $cfg->{EE}{demonKey});
if (!$db->connect) {
	$m->note($!) if $user->{admin};
	$m->error('Could not connect to database. Please try again later.');
}

my $languages = $db->askLanguages();

$languages or $m->error("Could not connect to database. Please try again later.");
my $lc = $m->paramStr('lc');
$lc or $m->error('No lc specified');
exists $languages->{$lc} or $m->error("Invalid LC.");
my $font = "./K5p3Ni2FIJt3mB5D3TA6FyV60m6w57.ttf";
#~ my $font = "./IAZWgK8TTg7Avl559s3E.ttf";
my $img = newFromPng GD::Image("bimg.png", 1);

my ($twords) = $m->fetchArray("SELECT COUNT(id) FROM dictWordLoc WHERE (arg1 != '' OR arg2 != '' OR 	arg3 != '' OR arg4 != '' OR arg5 != '' OR arg6 != '' OR arg7 != '' OR arg8 != '' OR arg9 != '' OR arg10 != '' OR odd != '' OR editTime < (SELECT editTime FROM dictWordMeta AS m WHERE m.id = id)) AND `lc` = ?", $lc);
my ($totalwords) = $m->fetchArray('SELECT COUNT(id) FROM dictWordMeta');
my $procent = sprintf("%d", $twords/$totalwords*100);

$twords > 0 or $m->error("Invalid language.");
my ($mt) = $m->fetchArray("SELECT MAX(editTime) FROM dictWordLoc WHERE lc = ?", $lc);

my $white = $img->colorAllocate(255, 255, 255);
my $awhite = $img->colorAllocateAlpha(255, 255, 255, 100);
$img->stringFT($white, $font, 13, 0, 10, 23, "$languages->{$lc}{nat} ($languages->{$lc}{eng})", {charmap => 'Unicode'});
$img->stringFT($white, $font, 8, 0, 10, 55, sprintf("Progress: %d%%\r\n(%d/%d words  translated)", $procent, $twords, $totalwords), {linespacing => 1.5, kerning => 0});
$img->stringFT($white, $font, 8, 0,  380, 55, "Last update:");
$img->stringFT($white, $font, 8, 0, 375, 70, $time{"Mon. d, yyyy", $mt});
#~ $img->stringFT($white, $font, 10, 0, 300, 10, $GD::VERSION);
$img->filledRectangle(10, 30, 440, 39, $awhite);
$img->filledRectangle(10, 30, int(440/100*$procent), 39, $white) if $procent > 0;

$m->printHttpHeader({'Content-type' => 'image/png'});
binmode STDOUT;
print $img->png(9);

$m->finish();