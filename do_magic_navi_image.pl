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

# Init
my ($m, $cfg, $lng, $user, $userId) = MwfMain->new(@_);

my $lc = $m->paramStr('lc');
$lc or $m->error('No lc specified');

my $bimg = newFromPng GD::Image("bimg.png", 1);
my $img = new GD::Image($bimg->width, $bimg->height, 1);
my $fimg = newFromPng GD::Image("fimg.png", 1);

$img->copy($bimg, 0, 0, 0, 0, $img->width, $img->height);

my $white = $img->colorAllocate(255, 255, 255);
my ($procent) = ($m->fetchArray("SELECT COUNT(id) FROM dictWordLoc WHERE (arg1 != '' OR arg2 != '' OR 	arg3 != '' OR arg4 != '' OR arg5 != '' OR arg6 != '' OR arg7 != '' OR arg8 != '' OR arg9 != '' OR arg10 != '' OR odd != '' OR editTime < (SELECT editTime FROM dictWordMeta AS m WHERE m.id = id)) AND `lc` = ?", $lc))[0]/($m->fetchArray('SELECT COUNT(id) FROM dictWordMeta'))[0]*100;

$procent > 0 or $m->error('Invalid language.');

$img->string(gdLargeFont, 5, 5, sprintf("Progress: %.1f%%", $procent), $white);
$img->string(gdLargeFont, 5, 40, "Language: $lc", $white);

my $pimg = newFromPng GD::Image("pimg.png", 1);
my $pi = new GD::Image($pimg->width, $pimg->height);
my ($pr, $pg, $pb, $pa) = (255-int($procent * 255/100), int($procent * 255/100), 0, int(0x7f/2));

my $pc = $pi->colorAllocateAlpha($pr, $pg, $pb, $pa);
$pi->filledRectangle(0, 0, $pi->width, $pi->height, $pc);
$pimg->copy($pi, 0, 0, 0, 0, $pi->width, $pi->height);

for (my $i = 0; $i < int($procent); ++$i) {
	$img->copy($pimg, 10+$i*$pimg->width, 25, 0, 0, $pimg->width, $pimg->height);
}

my ($mt) = $m->fetchArray("SELECT MAX(editTime) FROM dictWordLoc WHERE lc = ?", $lc);
$img->string(gdLargeFont, 280, 40, "Last Update: " . $time{"dd.mm.yyyy", $mt}, $white);

# And the final image ontop
$img->copy($fimg, 0, 0, 0, 0, $fimg->width, $fimg->height);

$m->printHttpHeader({'Content-type' => 'image/png'});
binmode STDOUT;
print $img->png;

$m->finish();