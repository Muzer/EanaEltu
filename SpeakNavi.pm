# SpeakNavi.pm, part of Eana Eltu by Tobias Jaeggi (Tuiq, tuiq at clonk2c dot ch), Richard Littauer (Taronyu, richard@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ).
# The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .
#
# This package contains all functions to provide Navi<->English.
# ITS AWESOME LIKE HELL.

use strict;
use Data::Dumper;
use DBI;
use Encode;

package SpeakNavi;

our $DEBUG = 0;

our $WRONGISR = 'iìIÌ';
our $WRONGIS = '['.$WRONGISR.']';
our $WRONGASR = 'aäAÄ';
our $WRONGAS = '['.$WRONGASR.']';
our $WRONGSEPSR = '\'';
our $WRONGSEPS = '['.$WRONGSEPSR.']';

our $VOWELS = "[eou]|${WRONGIS}|${WRONGAS}|ll|rr";
our $CONSONANTS = "[ptk]x|ng|[pmwtnrlkhy']";
our $DIPHTONGS = "[ae][wy](?:$CONSONANTS)?";
our $FRICATIVES = "(?:(?:[fvszh]|ts)(?:[ptk]x?|ng|[mnwlry])?)";

our $INFIXES1;
our $INFIXES2;
our $INFIXES3;
our $NAVICHARS = "aefhiklmnoprstuvwyzxgAEFHIKLMNOPRSTUVWYZXG${WRONGISR}${WRONGASR}${WRONGSEPSR} ";

our %INFIXES = ();
our %PREAFFIXES = ();
our %POSTAFFIXES = ();

# These languages are available later, loaded from the database.
our %LANGUAGES = ();

# Number magic - hardcoding is fun.
our %NUMBERS = (
	p1 =>    {0 => '', 1 => '\'aw', 		2 => 'mune', 		3 => 'pxey', 		 4 => 'tsìng',    5 => 'mrr', 		 6 => 'pukap',   7 => 'kinä'},
	p1x =>   {0 => '', 1 => 'aw',   		2 => 'mun', 		3 => 'pey', 		 4 => 'sìng',     5 => 'mrr',      6 => 'fu',      7 => 'hin'},
	p8 =>    {0 => '', 1 => 'vo',  		2 => 'mevo', 	3 => 'pxevo',   4 => 'tsìvo',   5 => 'mrrvo',   6 => 'puvo',   7 => 'kivo'},
	p64 =>   {0 => '', 1 => 'zam',  		2 => 'mezam', 	3 => 'pxezam', 	 4 => 'tsìzam',   5 => 'mrrzam',   6 => 'puzam',   7 => 'kizam'},
	p512 =>  {0 => '', 1 => 'vozam', 	2 => 'mevozam', 3 => 'pxevozam', 4 => 'tsìvozam', 5 => 'mrrvozam', 6 => 'puvozam', 7 => 'kivozam'},
	p4096 => {0 => '', 1 => 'zazam', 2 => 'mezazam', 3 => 'pxezazam', 4 => 'tsìzazam', 5 => 'mrrzazam',  6 => 'puzazam', 7 => 'kizazam'},
	p32768 => {0 => '', 1 => 'vozazam', 2 => 'mevozazam', 3 => 'pxevozazam', 4 => 'tsìvozazam', 5 => 'mrrvozazam', 6 => 'puvozazam', 7 => 'kivozazam'},
);

# Regex - identifies a string as a possible number
our $NUMBERREGEX = join '|', grep { $_ ne '' } ('vol', values %{$NUMBERS{p1x}});

our @NUMBERORDERING = qw(p1 p1x p8 p64 p512 p4096 p32768);

# Instant. NOW.
$| = 1;
{
	my $ofh = select STDERR;
	$| = 1;
	select $ofh;
}

sub numToNavi {
	my ($input) = @_;
	# Octal?
	if ($input =~ /^0o([0-7]+)$/ || $input =~ /^o([0-7]+)$/ || $input =~ /^0([0-7]+)$/) {
		return octToNavi($1);
	}
	if ($input =~ /^[0-9]+$/) {
		return decToNavi($input);
	}
	return 'Ke holpxay.';
}

sub naviToNum {
	my ($input) = @_;
	my $output = 0;
	for my $key (reverse grep { $_ ne 'p1x' && $_ ne 'p1' } @NUMBERORDERING) {
		for (my $i = 1; $i <= 7;  $i++) {
			die "Undef NumKey: $key / $i!" if !exists($NUMBERS{$key}{$i});
			my $v = quotemeta($NUMBERS{$key}{$i});
			if ($input =~ /^$v/ || "m$input" =~ /^$v/) {
				if ($input !~ /^$v/) {
					my $lv = substr $v, 1;
					$input =~ s/^$lv//;
				}
				else {
					$input =~ s/^$v//;
				}
				$input =~ s/^l// if $v =~ /vo$/;
				$output += substr($key,1) * $i;
				last;
			}
		}
	}
	
	if ($input) {
		# We could try against p1 / p1x
		if ($output == 0) {
			for (my $i = 1; $i <= 7; $i++) {
				my $v = quotemeta($NUMBERS{p1}{$i});
				if ($input =~ /^$v/) {
					$input =~ s/^$v//;
					$output = $i;
					last;
				}
			}
		}
		else {
			for (my $i = 1; $i <= 7; $i++) {
				my $v = quotemeta($NUMBERS{p1x}{$i});
				if ($input =~ /^$v/) {
					$output += $i;
					$input =~ s/^$v//;
					last;
				}
			}
		}
	}
	
	print "NUMBER: $input unparsed!\n" if $input ne '';
	return undef if $input ne '';
	return $output;
}

# 'aw - mune - pxey - tsìng - mrr - pukap - kinä - vol
#   1 -    2 -    3 -     4 -   5 -    6  -    7 -  10
# vol-aw - vo-mun - vo-pey - vo-sìng - vo-mrr - vo-fu - vo-hin - me-vol
#     11 -     12 -     13 -      14 -     15 -    16 -     17 -     20
# pxe-vol-aw - pxe-vo-mun - ... - tsì-vol
#         31 -         32 -     -      40
sub octToNavi {
	my ($number) = @_;
	return 'Oel keomum fiholypaxìl.' if $number <= 0 || log($number)/log(10) >= 6;
	# Left-to-right
	my $navi = '';
	my $digits = length $number;
	for (my $i = 0; $i < $digits; $i++) {
		my $rdv = 8**($digits-$i-1);
		my $d = substr $number, $i, 1;
		my $np = '';
		if ($rdv == 1 && $digits > 1) {
			warn "ERROR: p1x - $d" if !defined $NUMBERS{p1x}{$d};
			$np = $NUMBERS{p1x}{$d};
		} elsif ($rdv == 1) {
			$np = $NUMBERS{p1}{$d};
			warn "ERROR: p1 - $d" if !defined $NUMBERS{p1}{$d};
		} else {
			$np = $NUMBERS{"p$rdv"}{$d};
			warn "ERROR: $rdv - $d" if !defined $NUMBERS{"p$rdv"}{$d};
		}
		$navi .= 'l'  if $np =~ /^aw/ && $navi =~ /vo$/;
		$np =~ s/^m// if $np =~ /^m/ && $navi =~ /m$/;
		$navi .= $np;		
	}
	$navi .= 'l' if $navi =~ /vo$/;
	return $navi; # . " ($number oct, " . oct($number) . " dec : d " . $dbg . ")";
}

sub decToNavi {
	my ($number) = @_;
	return '' if $number <= 0;
	$number = sprintf("%o", $number);
	return octToNavi($number);
}

sub array_unique {
	my %_uniquef;
	return grep { !$_uniquef{$_}++ } @_;
}

our @VERBMODIFIERS = qw(VERB V);
our @ATTENTIONWORDS = ();
our @LISTEDATTENTIONWORDS = ();

# Outdated, mostly not used (exceptions for LEN and other hardcoded things)
# 2do: move them into the database
our %SHORTTERMS = (
	AWAY => ['AWAY', 'AWAY', 'Away.'],
	ACC => ['ACC', 'ACC', 'Accusative.'],
	ADJM => ['ADJ.M', 'ADJ M', 'Adjective attributed.'],
	ADJ => ['ADJ', 'ADJ', 'Derived adjective.'],
	ADV => ['ADV', 'ADV', 'Derived adverbial.'],
	AGENTN => ['AGENT.N', 'AGENT N', 'Derived nominative agent noun.'],
	CLU => ['CLU', 'CLU', 'Pronounal clusivity.'],
	DAT => ['DAT', 'DAT', 'Dative.'],
	DUAL => ['DUAL', 'DUAL', 'Dual.'],
	ERG => ['ERG', 'ERG', 'Eregative case.'],
	FEM => ['FEM', 'FEM', 'Feminime.'],
	FUT => ['FUT', 'FUT', 'Future tense.'],
	GEN => ['GEN', 'GEN', 'Genetive.'],
	IMMFUT => ['IMM.FUT', 'IMM. FUT', 'Immediate future tense.'],
	IMPF => ['IMPF', 'IMPF', 'Imperfective.'],
	IMPFPAST => ['IMPF.PAST', 'IMPF. PAST', 'Impferfective past'],
	IMPFRECPAST => ['IMPF.REC.PAST', 'IMPF. REC. PAST', 'Imperfective recent past tense'],
	INST => ['INST', 'INST', 'Instrumental.'],
	INTER => ['INTER', 'INTER', 'Question marker.'],
	LAUD => ['LAUD', 'LAUD', 'Laudative (yay).'],
	MASC => ['MASC', 'MASC', 'Masculine.'],
	NMLZ => ['NMLZ', 'NMLZ', 'Nominalized.'],
	OBJ => ['OBJ', 'OBJ', 'Direct object.'],
	PART => ['PART', 'PART', 'Participle.'],
	PAST => ['PAST', 'PAST', 'Past tense.'],
	PEJ => ['PEJ', 'PEJ', 'Pejorative (ugh).'],
	PERF => ['PERF', 'PERF', 'Perfective.'],
	PLU => ['PLU', 'PLU', 'Plural.'],
	RECPAST => ['REC.PAST', 'REC. PAST', 'Recent past'],
	SUBJ => ['SUBJ', 'SUBJ', 'Subjunctive.'],
	TOP => ['TOP', 'TOP', 'Topic.'],
	V => ['V', 'V', 'Derived verb.'],
	VOC => ['VOC', 'VOC', 'Vocative.'],
	ONE => ['ONE', 'ONE', 'One.'],
	EVERY => ['EVERY', 'EVERY', 'Adposition: every.'],
	PATHDIRECTION => ['PATH.DIRECTION', 'PATH DIRECTION', 'Path, Direction.'],
	NOTONE => ['NOT.ONE', 'NOT ONE', 'Adposition: not one.'],
	NOT => ['NOT', 'NOT', 'Adposition: not.'],
	GROUND => ['GROUND', 'GROUND', 'Ground.'],
	OTHER => ['OTHER', 'OTHER', 'Adposition: other.'],
	EXCEPT => ['EXCEPT', 'EXCEPT', 'Adposition: except.'],
	COMPARATIVE => ['COMPARATIVE', 'COMPARATIVE', 'Adposition: comparative adjectival marker.'],
	SAMEWAYAS => ['SAME.WAY.AS', 'SAME WAY AS', 'Adposition: same way as.'],
	ABOUT => ['ABOUT', 'ABOUT', 'Adposition: about.'],
	THAT => ['THAT', 'THAT', 'Adposition: that.'],
	UPTO => ['UP.TO', 'UP TO', 'Adposition: up to.'],
	THESE => ['THESE', 'THESE', 'Adposition: these.'],
	FROMDIRECTION => ['FROM.direction', 'FROM DIRECTION', 'Adposition/preposition: from (direction).'], # 'ftu' could cause that too, and that's a preposition
	OTHERS => ['OTHERS', 'OTHERS', 'Adposition: others.'],
	IN => ['IN', 'IN', 'Preposition: in.'],
	WHAT => ['WHAT', 'WHAT', 'Affix inter. marker: what.'],
	TRIAL => ['TRIAL', 'TRIAL', 'Trial.'],
	THOSE => ['THOSE', 'THOSE', 'Adposition: those.'],
	ABOVE => ['ABOVE', 'ABOVE', 'Preposition: above.'],
	BEFOREINFRONTOF => ['BEFORE.in.front.of', 'BEFORE, IN FRONT OF', 'Preposition: before, in front of.'],
	WITHBYMEANSOF => ['WITH.BY.MEANS.OF', 'WITH, BY MEANS OF', 'Preposition: with, by means of.'],
	FORTHESAKEOF => ['FOR.THE.SAKE.OF', 'FOR THE SAKE OF', 'Preposition: for the sake of.'],
	WITHACCOMPANIMENT => ['WITH.accompaniment', 'WITH, ACCOMPANIMENT', 'Preposition: with (accompaniment).'],
	BYVIAFOLLOWING => ['BY.VIA.FOLLOWING', 'BY, VIA, FOLLOWING', 'Preposition: by, via, following.'],
	BEHINDBACK => ['BEHIND.BACK', 'BEHIND, BACK', 'Preposition: behind, back.'],
	ACROSS => ['ACROSS', 'ACROSS', 'Preposition: across.'],
	AMONG => ['AMONG', 'AMONG', 'Preposition: among.'],
	CLOSECLOSETO => ['CLOSE.CLOSE.TO', 'CLOSE, CLOSE TO', 'Preposition: close, close to.'],
	AWAYPOSITION => ['AWAY.POSITION', 'AWAY POSITION', 'Preposition: away (position).'],
	LIKEAS => ['LIKE.AS', 'LIKE, AS', 'Preposition: Like, as'],
	TOTOWARDS => ['TO.TOWARDS', 'TO, TOWARDS', 'Preposition: to, towards.'],
	BACKDIRECTION => ['BACK.direction', 'BACK DIRECTION', 'Preposition: back (direction).'],
	AWAYDIRECTION => ['AWAY.direction', 'AWAY DIRECTION', 'Preposition: away (direction).'],
	FROMVARIOUS => ['FROM.various', 'FROM VARIOUS', 'Preposition: from (various uses).'],
	AWAYFROM => ['AWAY', 'AWAY', 'Preposition: away from.'],
	UNDER => ['UNDER', 'UNDER', 'Preposition: under.'],
	REFL => ['REFL', 'REFL', 'Reflexive.'],
	LEN => ['LEN', 'LEN', 'Lenited.'],
	CONT => ['CONT', 'CONT', 'Contradicted.'],
	UNKNOWN => ['Unknown', 'Unknown', '<b>Bug. Please report that %s hasn\'t been found.</b>'],
	THIS => ['THIS', 'THIS', 'Adposition: This.'],
	CER => ['CER', 'CER', 'Honorific or ceremonial.'],
	CAUS => ['CAUS', 'CAUS', 'Causative.'],
	INFR => ['INFR', 'INFR', 'Inferential, indicating uncertainty or indirect knowledge'],
);

sub openMySQLDatabase {
	my ($self, $database, $username, $password) = @_;
	my $ref = {'words' => [], 'type' => 'mysql', 'dbh' => undef};
	$ref->{dbh} = DBI->connect("DBI:mysql:$database", $username, $password) or die "Error connecting to database: " . DBI->errstr . "\n";
	refreshMySQLDatabase($ref);
	return $ref;
}

sub refreshMySQLDatabase {
	my ($ref) = @_;
	my @words;
	
	my $dbh = $ref->{dbh};
	
	# Very first of everything: Get languages.
	my $lsth = $dbh->prepare('SELECT * FROM dictLanguages');
	$lsth->execute();
	
	while (my $r = $lsth->fetchrow_hashref()) {
		$LANGUAGES{$r->{lc}} = {eng => $r->{engName}, nat => $r->{nativeName}, active => $r->{active}};
	}
	
	# First of all: Get all infixes.
	my $isth = $dbh->prepare("SELECT * FROM dictWordMeta WHERE `type` = 'infixN' && block = '2'");
	my $listh = $dbh->prepare('SELECT * FROM dictWordLoc WHERE id = ?');
	
	$isth->execute();
	
	%INFIXES = ();
	@ATTENTIONWORDS = ();
	@LISTEDATTENTIONWORDS = ();
	while (my $r = $isth->fetchrow_hashref()) {
		# Get rid of this ugly tex.
		#~ $r->{arg1} =~ s/[\$<>]//go;
		#~ $r->{arg2} =~ s/[^A-Z]//go;
		$r->{arg4} = 0 if $r->{arg4} eq 'pre-first';
		$INFIXES{$r->{arg4}} = [] if !exists $INFIXES{$r->{arg4}};
		my %ir = (inf => $r->{arg1}, pos => $r->{arg4}, sc => $r->{arg8}, desc => $r->{arg3}, publish => 1);
		$listh->execute($r->{id});
		while (my $lr = $listh->fetchrow_hashref()) {
			$ir{"desc$lr->{lc}"} = $lr->{arg3};
		}
		push @{$INFIXES{$ir{pos}}}, \%ir;
		push @VERBMODIFIERS, $ir{sc};
		$INFIXES{$ir{sc}} = \%ir;
		$INFIXES{$ir{inf}} = \%ir;
		$SHORTTERMS{$ir{sc}} = [$ir{sc}, $ir{sc}, $ir{desc}, \%ir];
		if ($ir{inf} =~ /i$/) {
			my %sir = %ir;
			$sir{inf} .= 'y';
			$sir{publish} = 0;
			$INFIXES{$sir{sc}} = \%sir;
			$INFIXES{$sir{inf}} = \%sir;
			push @{$INFIXES{$sir{pos}}}, \%sir;
		}
	}
	
	my $eisth = $dbh->prepare("SELECT * FROM dictWordMeta WHERE `type` = 'infixcwN' && block = '2'");
	my $leisth = $dbh->prepare('SELECT * FROM dictWordLoc WHERE id = ?');
	
	$eisth->execute();
	while (my $r = $eisth->fetchrow_hashref()) {
		my ($a, $b) = ($INFIXES{$r->{arg5}}, $INFIXES{$r->{arg6}});
		#~ $r->{arg1} =~ s/[\$<>]//go;
		#~ $r->{arg2} =~ s/[^A-Z]//go;		
		my %ir = (inf => $r->{arg1}, pos => $r->{arg4}, sc => $r->{arg10}, desc => $r->{arg3}, publish => 1);
		$leisth->execute($r->{id});
		while (my $lr = $leisth->fetchrow_hashref()) {
			$ir{"desc$lr->{lc}"} = $lr->{arg3};
		}		
		push @{$INFIXES{$ir{pos}}}, \%ir;
		$INFIXES{$ir{sc}} = \%ir;
		$INFIXES{$ir{inf}} = \%ir;
		$SHORTTERMS{$ir{sc}} = [$ir{sc}, $ir{sc}, $ir{desc}, \%ir];
		if ($ir{inf} =~ /i$/) {
			my %sir = %ir;
			$sir{inf} .= 'y';
			$sir{publish} = 0;
			$INFIXES{$sir{sc}} = \%sir;
			$INFIXES{$sir{inf}} = \%sir;
			push @{$INFIXES{$sir{pos}}}, \%sir;
		}
	}
	$INFIXES{s0} = $INFIXES1 = join '|', map { quotemeta($_->{inf}) } grep { $_->{publish} } @{$INFIXES{0}};
	$INFIXES{s1} = $INFIXES2 = join '|', map { quotemeta($_->{inf}) } grep { $_->{publish} } @{$INFIXES{1}};
	$INFIXES{s2} = $INFIXES3 = join '|', map { quotemeta($_->{inf}) } grep { $_->{publish} } @{$INFIXES{2}};
	print "Prepared infixes!\n";
	print "1: $INFIXES1\n";
	print "2: $INFIXES2\n";
	print "3: $INFIXES3\n";

	# NOUN MAGIC
	%PREAFFIXES = %POSTAFFIXES = ();
	my $afsth = $dbh->prepare("SELECT * FROM dictWordMeta WHERE block = 3 || block = 4 || type = 'pcw' || type = 'pderives'");
	my $lafsth = $dbh->prepare('SELECT * FROM dictWordLoc WHERE id = ?');
	
	$afsth->execute();
	while (my $r = $afsth->fetchrow_hashref()) {
		$lafsth->execute($r->{id});
		
		my $af = {afx => $r->{arg1}};
		$af->{afx} =~ s/^\-\-|\+$|\-\-$//go;
		$af->{afx} =~ s/^\-|\-$//go;
		
		next if $af->{afx} eq 'si';
		
		if ($r->{type} =~ /^alloffix/) {
			$af->{sdesc} = $r->{arg9};
			$af->{desc} = $r->{arg4};
			while (my $lr = $lafsth->fetchrow_hashref()) {
				$af->{"desc$lr->{lc}"} = $lr->{arg4};
			}
		}
		elsif ($r->{type} =~ /^affix/) {
			$af->{desc} = $r->{arg3};
			$af->{sdesc} = $r->{arg8};
			while (my $lr = $lafsth->fetchrow_hashref()) {
				$af->{"desc$lr->{lc}"} = $lr->{arg3};
			}
		}
		elsif ($r->{type} =~ /^marker/) {
			$af->{desc} = $r->{arg3};
			$af->{sdesc} = $r->{arg7};
			while (my $lr = $lafsth->fetchrow_hashref()) {
				$af->{"desc$lr->{lc}"} = $lr->{arg3};
			}
		}
		elsif ($r->{type} =~ /^derivingaffix/) {
			$af->{desc} = $r->{arg3};
			$af->{desc} =~ s/^\([0-9]+\) //o;
			$af->{sdesc} = $r->{arg7};
			while (my $lr = $lafsth->fetchrow_hashref()) {
				$af->{"desc$lr->{lc}"} = $lr->{arg3};
				$af->{"desc$lr->{lc}"} =~ s/^\([0-9]+\) //o;
			}			
		}
		elsif ($r->{type} eq 'pword') {
			$af->{desc} = $r->{arg4};
			$af->{sdesc} = $r->{arg6};
			while (my $lr = $lafsth->fetchrow_hashref()) {
				$af->{"desc$lr->{lc}"} = $lr->{arg4};
			}
		}
		elsif ($r->{type} eq 'pcw') {
			$af->{desc} = $r->{arg4};
			$af->{sdesc} = $r->{arg10};
			while (my $lr = $lafsth->fetchrow_hashref()) {
				$af->{"desc$lr->{lc}"} = $lr->{arg10};
			}
		}
		elsif ($r->{type} eq 'pderives') {
			$af->{desc} = $r->{arg4};
			$af->{sdesc} = $r->{arg8};
			while (my $lr = $lafsth->fetchrow_hashref()) {
				$af->{"desc$lr->{lc}"} = $lr->{arg4};
			}
		}
		else {
			die "Unimplemented affix type $r->{type}!";
		}
		
		if ($r->{arg1} =~ /^\-\-/ && $r->{arg1} !~ /\-\-$/) {
			# Prefix
			$POSTAFFIXES{$af->{afx}} = $af;
			#~ print "POSTFIX $af->{afx}\n";
		}
		elsif ($r->{arg1} =~ /^\-.+\-$/) {
			$PREAFFIXES{$af->{afx}} = $af;
			$POSTAFFIXES{$af->{afx}} = $af;			
		}
		elsif ($r->{arg1} =~ /\+$/ || $r->{arg1} =~ /\-\-$/) {
			$PREAFFIXES{$af->{afx}} = $af;
			#~ print "PREFIX $af->{afx}\n";
		}
		else {
			#~ print "BOTHFIX $af->{afx}\n";
			$PREAFFIXES{$af->{afx}} = $af;
			$POSTAFFIXES{$af->{afx}} = $af;
		}
		
		my $csd = $af->{sdesc};
		$csd or die "Could not create csd for $csd->{desc} ($csd->{afx})";
		$csd =~ s/ {2,}/ /go;
		$csd =~ s/ /./go;
		$SHORTTERMS{$af->{sdesc}} = [$af->{sdesc}, $csd, $af->{desc}, $af];
	}
	print "Handling postfixes ", join(', ', keys %POSTAFFIXES), " and prefixes ", join(', ', keys %PREAFFIXES), "\n";
	print "Prepared affixes!\n";
	print "Oh, by the way: $NUMBERREGEX\n";
	
	my $sth = $dbh->prepare('SELECT * FROM dictWordMeta WHERE block = 0 || block = 9 || block = 7 || block = 8 || id = 294 || id = 511 || id = 556 ORDER BY id ASC'); # Nur "Standardwörter".
	$sth->execute();
	
	my $ssth = $dbh->prepare('SELECT * FROM dictWordLoc WHERE id = ? && lc IN (' . join(',', map { '\'' . $_ . '\'' } grep { $LANGUAGES{$_}{active} } keys %LANGUAGES) . ')');
	my $asth = $dbh->prepare("SELECT * FROM dictWordLoc WHERE id = ? && lc = 'nav'");
	
	my ($r, $s);
	my $idOffset = 0;
	while ($r = $sth->fetchrow_hashref()) {
		# Skip some.
		next if $r->{type} !~ /^(?:word|loan|lenite|derives?|deriveall|note|cw|cww|cwww)$/ && $r->{id} != 447 && $r->{id} != 556;
		next if $r->{type} eq 'derivingaffix' && ($r->{arg1} ne 'si');
		#~ for my $u (values %$r) { 
			#~ utf8::encode($u) if defined $u;
		#~ }
		my %word;
		my $lcField;
		my $type;
		if ($r->{type} eq 'deriveall') {
			$lcField = 'arg5';
		}
		elsif ($r->{type} eq 'derivingaffix' || $r->{type} eq 'marker') {
			$lcField = 'arg3';
		}
		else {
			$lcField = 'arg4';
		}
		
		if ($r->{type} eq 'marker' || $r->{type} eq 'derivingaffix') {
			$type = '';
		}
		else {
			$type = $r->{arg3};
		}
		#~ \note{s\`i=}{sI}{conj.}{and}{connects two things: for clauses use, can be attached as --s\`i}{ulte}{and}{S} 
		$word{nav} = texToPerl($r->{arg1});
		#~ $word{nav} =~ s/^[*-=+]+//o; # This may be a bit unhealthy
		#~ $word{nav} =~ s/[*-=+]+$//o; # UNHEALTHY
		$word{qnav} = quotemeta($word{nav});
		$word{ipa} = tipaToPerl($r->{arg2});
		$word{type} = $type;
		$word{eng} = texToPerl($r->{$lcField});
		$word{eng} .= ' (' . texToPerl($r->{'arg5'}) . ')' if $r->{type} eq 'note';
		#~ $word{eng} =~ s/\\[A-Za-z]+//go;
		#~ $word{eng} =~ s/[{}]//go;
		$word{reng} = SpeakNavi::denavizes($word{eng});
		$word{typeeng} = $word{type};
		$word{eeng} = prepareEL($word{eng});
		$word{svnav} = undef;
		$word{snav} = undef;
		$word{vnav} = undef;
		$word{composed} = undef;
		$word{id} = $r->{id}+$idOffset;
		
		$ssth->execute($r->{id});
		# Go get these wussies.
		while ($s = $ssth->fetchrow_hashref()) {
			my $lc = $s->{lc};
			print "ALERT!", ::Dumper($r, $s) if !defined $s->{$lcField};
			$word{$lc} = texToPerl($s->{$lcField});
			$word{$lc} .= ' (' . $r->{'arg5'} . ')' if $r->{type} eq 'note';
			$word{"r$lc"} = SpeakNavi::denavizes($word{$lc});
			$word{"type$lc"} = $r->{type} eq 'derivingaffix' ? '' : $s->{arg3};
			$word{"e$lc"} = prepareEL($word{$lc});
		}
		#~ #/APRILSCHERZ
		
		if ($word{nav} =~ /^(.*?)\((.*?)\)$/) {
			my ($pr, $po) = ($1, $2);
			$word{nav} = $pr;
			$word{qnav} = quotemeta($word{nav});
			my %w = %word;
			push @words, \%w;
			$word{id}++;
			$idOffset++;
			$word{nav} = $pr.$po;
			$word{qnav} = quotemeta($word{nav});
		}
		push @words, \%word;
	}
	
	# Refine
	for my $word (@words) {
		my @types = split ', ', $word->{type};
		my @parts = split / +/, $word->{nav};
		
		if ((scalar grep { $_ =~ /^s?v(?:tr|in)?\./ || $_ =~ /verb/ } @types) || $word->{nav} eq 'si' && scalar @parts <= 3) {
			#~ print "Verb.\n";
			#~ print "Desyll: ", join('-', SpeakNavi::desyll($word->{nav})), "\n";
			my $ipa = $word->{ipa};
			utf8::encode($ipa);
			$ipa =~ s/\].*//; # Remove alternative pronunciations, just take first
			my @ipaparts = split / /, $ipa;
			#~ print "IPAP: ", join('-', @ipaparts), "\n";
			#~ print "P: ", join('-', @parts), "\n";
			die "Mismatched number of parts for $word->{nav}" if @parts != @ipaparts;
			#~ print "Got $#parts for $word->{nav}\n";
			for my $i (0..$#parts) {
				#~ print "Pants($i): ", $parts[$i], "\n";
				my @sylls = SpeakNavi::desyll($parts[$i]);
				#~ print "PANTZ: ", join('-', @sylls), "\n";
				my $infixcount = () = $ipaparts[$i] =~ /Â·/g;
				#~ print ::Dumper($ipaparts[$i] =~ /Â·/g);				
				if ($infixcount == 2) {
					eval {
						$sylls[-2] =~ s/($VOWELS)/<1><2>$1/o;
						$sylls[-1] =~ s/($VOWELS)/<3>$1/o;
					};
					if ($@) {
						die "$@ : " . ::Dumper($word,  \@parts,\@ipaparts, \@sylls);
					}
				}
				elsif ($infixcount == 1) {
					$sylls[-1] =~ s/($VOWELS)/<1><2><3>$1/o;
				}
				$parts[$i] = join '', @sylls;
			}
			$word->{svnav} = join ' ', @parts;
			$word->{vnav} = svnavToVNAV($word->{svnav});
			#~ binmode STDOUT, ':utf8';
			#~ print "$word->{svnav} for $word->{nav} [$word->{ipa}]\n";
			#~ binmode STDOUT, ':ascii';
		}		
		
		# Noun? Pronoun? Lenition!
		if ($word->{nav} ne leniteWord($word->{nav}) && (!scalar @types || scalar grep { $_ eq 'prop.n.' || $_ eq 'n.' || $_ eq 'pn.' || $_ =~ /pronoun/ } @types)) {
			#~ print "Lenition: '$word->{nav}' | $word->{eng}\n";
			$word->{lnav} = leniteWord($word->{nav});
			$word->{qlnav} = quotemeta($word->{lnav});
		}
		
		# Pronoun? Shortcut.
		if (!scalar @types || (scalar grep { $_ eq 'pn.' || $_ =~ /pronoun/ } @types) && (scalar desyll($word->{nav}) == 1)) {
			#~ print "Shortcut: '$word->{nav}' | $word->{eng}\n";
			$word->{snav} = substr $word->{nav}, 0, -1;
		}
		
		# ITS TORN APART ONOES
		if ($word->{nav} =~ / /) {
			push @ATTENTIONWORDS, split / /, $word->{nav};
			push @LISTEDATTENTIONWORDS, $word;
		}		
	}
	@ATTENTIONWORDS = array_unique(@ATTENTIONWORDS);
	print "Words to pay attention: ", join(' ', @ATTENTIONWORDS), "\n";
	$ref->{words} = \@words;
	
	bless $ref;
}

sub svnavToVNAV {
	my ($text) = @_;
	my ($I1, $I2, $I3) = ($SpeakNavi::INFIXES1, $SpeakNavi::INFIXES2, $SpeakNavi::INFIXES3);
	my $addText = '';
	# seiyi
	if ($text =~ /<3>i/) {
		$I3 =~ s/i\|/iy\|/go;
		$I3 =~ s/i$/iy/o;
	}
	if ($text =~ /<[1-3]>ll/) {
		my $I1Infected = $text =~ /<1>ll/;
		my $I2Infected = $text =~ /<2>ll/;
		my $I3Infected = $text =~ /<3>ll/;
		my $IL1 = join '|', map { $_->{inf} !~ /l$/ && $I1Infected ? quotemeta($_->{inf}) . '(?:ll)' : quotemeta($_->{inf}) } grep { $_->{publish} } @{$INFIXES{0}};
		my $IL2 = join '|', map { $_->{inf} !~ /l$/ && $I2Infected ? quotemeta($_->{inf}) . '(?:ll)' : quotemeta($_->{inf}) } grep { $_->{publish} } @{$INFIXES{1}};
		my $IL3 = join '|', map { $_->{inf} !~ /l$/ && $I3Infected ? quotemeta($_->{inf}) . '(?:ll)' : quotemeta($_->{inf}) } grep { $_->{publish} } @{$INFIXES{2}};
		# EVIL VOODOO GOING ON HERE
		$addText = '|'.$text;
		$addText =~ s/<([1-3])>ll/<$1>/go;
		$addText =~ s/<1>/($IL1)?/;
		$addText =~ s/<2>/($IL2)?/;
		$addText =~ s/<3>/($IL3)?/;
	}
	$text =~ s/<1>/($I1)?/;
	$text =~ s/<2>/($I2)?/;
	# VERY SPECIAL EXCEPTION
	$text =~ s/<3>/($I3)?/;
	$text .= $addText if $addText;
	return $text;
}

sub texToPerl {
	my ($text) = @_;
	#~ utf8::decode($text);
	$text =~ s/[\+\-=\*]//go;
	$text =~ s/\$phi\$//go;
	$text =~ s/\\[A-Za-z_]+ ?//go;
	$text =~ s/\$[<>]\$//go;
	$text =~ s/\$_\{?[A-Z]+\}?\$//go;
	$text =~ s/[{}]//go;
	utf8::decode($text);
	return $text;
}

sub prepareEL {
	my ($text) = @_;
	$text =~ s/[ ,]/./g;
	$text =~ s/\.\././g;
	return $text;
}

sub denavizes {
	my @_2 = @_;
	return denavize(\$_2[0], @_2[1..$#_]);
}
# Replaces common "errors" to unify everything.
sub denavize {
	my ($text, $full) = @_;
	$full = 1 if !defined $full;
	$$text = lc $$text;
	$$text =~ s/$WRONGIS/i/igo;
	$$text =~ s/$WRONGAS/a/igo;	
	if ($full) {
		$$text =~ s/\W//igo;
	} else {
		$$text =~ s/[^A-Za-z-.()]//igo;
	}
	$$text =~ s/[,.'"´`¨!?_]//igo;
	$$text =~ s/[()-]//go if $full;
	$$text = quotemeta($$text);
	return $$text;
}

{
	my $REGEX = undef;
	# Splits a word into syllables
	sub desyll {
		my ($text) = @_;
		my @syllables;
		$REGEX = "^((?:$FRICATIVES|$CONSONANTS)?(?:$VOWELS)(?:$DIPHTONGS)?)" if !defined $REGEX;

		while ($text =~ s/$REGEX//io) {
			my $syl = $1;
			if ($text !~ /$REGEX/i) {
				if ((my ($c) = $text =~ /^($CONSONANTS)/i) && $text !~ /^(?:$FRICATIVES)/i && $syl !~ /(?:$DIPHTONGS)$/i) {
					$syl .= $c;
					$text =~ s/^(?:$CONSONANTS)//io;
				}
			}
			
			push @syllables, $syl;
			if ($text !~ /$VOWELS/i) {
				if (length $text) {
					$syllables[$#syllables] .= $text;
					$text = '';
					last;
				}
			}
		}
		# If there is still text, it's in the last sybyll
		if (length $text) {
			push @syllables, $text;
		}
		return @syllables;
	}
}

# return:
# [
#   HASHREF pair,
#   SCALAR foundLanguageCode
# ]
sub advFindTranslations {
	my ($db, $inp, $searchLanguages, $exact) = @_;
	my @languages = @$searchLanguages;
	scalar @languages or die "You have to specify a input language.\n";
	
	if ($inp =~ /^\W+$/) {
		return ();
	}
	
	utf8::decode($inp);
	my $qinp = quotemeta($inp);
	
	my @directhits;
	my @reghits;
	
	for my $pair (@{$db->{words}}) {
		for my $lc (@languages) {
			if ($pair->{$lc} && lc $inp eq lc $pair->{$lc}) {
				push @directhits, [$pair, 1, $lc];
			}
			elsif ($pair->{$lc} && $pair->{$lc} =~ /$qinp/i) {
				push @reghits, [$pair, 0.5, $lc];
			}
		}
	}
	
	my @result;
	if (scalar @directhits) {
		#~ if (scalar @directhits < 150) {
			for my $pair (@directhits) {
				push @result, [@$pair[0,2]];
			#~ }
			return @result if $exact && scalar @result;
		}
	}
	if (scalar @reghits) {
		#~ if (scalar @reghits < 150) {
			for my $pair (@reghits) {
				push @result, [@$pair[0,2]];
			}
		#~ }
	}
	
	return @result;
}

#lnav und nav gemixxt: HACK
sub containsPrepost {
	my ($matchword, $prefix, $word, $postfix, $name, $mods) = @_;
	#~ print "ERROR IN CONTAINPREPOSTS!\n";
	#~ if (('LEN' ~~ @$mods && $$matchword =~ /$prefix$word->{qlnav}$postfix/) || $$matchword =~ /$prefix$word->{qnav}$postfix/i) {
	#~ binmode STDOUT, ':utf8';
	utf8::decode($prefix);
	#~ utf8::decode($word->{qnav});
	#~ utf8::decode($$matchword);
	utf8::decode($postfix);
	#~ utf8::encode($$matchword);
	#~ print "$$matchword =~ /", $prefix, $word->{qnav}, $postfix, "/i\n";
	#~ binmode STDOUT, ':crlf';
	if ($$matchword =~ /$prefix$word->{qnav}$postfix/i) {
		push @{$mods}, $name;
		#~ print "$name ELEMENT $$matchword\n";
		#~ if ('LEN' ~~ @$mods) {
			#~ $$matchword =~ s/$prefix$word->{qlnav}/$word->{nav}/i if $prefix ne '';
			#~ $$matchword =~ s/$word->{qlnav}$postfix/$word->{nav}/i if $postfix ne ''
		#~ } else {
			$$matchword =~ s/$prefix$word->{qnav}/$word->{nav}/i if $prefix ne '';
			$$matchword =~ s/$word->{qnav}$postfix/$word->{nav}/i if $postfix ne '';
		#~ }
		return 1;
	}
	return 0;
}

sub advStripWordDownNew {
	my ($orgword, $pair, $mods) = @_;
	my $ma = $orgword;
	my $changes = 1;
	
	while ($changes) {
		my $next = 0;
		for (sort { length $b <=> length $a } keys %PREAFFIXES) {
			if (containsPrepost(\$ma, $PREAFFIXES{$_}->{afx}, $pair, '', $PREAFFIXES{$_}->{sdesc}, $mods)) {
				$next = 1;
				last;
			}
		}
		next if $next;
		for (sort { length $b <=> length $a } keys %POSTAFFIXES) {
			if (containsPrepost(\$ma, '', $pair, $POSTAFFIXES{$_}->{afx}, $POSTAFFIXES{$_}->{sdesc}, $mods)) {
				$next = 1;
				last;
			}
		}
		next if $next;
		$changes = 0;
	}
	
	return $ma;
}

sub calcPriorityForStripped {
	my ($pair, $stripped, @mods) = @_;
	my $prio = scalar @mods;
	# I != O
	$prio += 50 if $pair->{nav} ne $stripped;
	# Subtract if it's a shortcut
	$prio -= 50 if ($pair->{snav} && $pair->{snav} eq $stripped);
	# "silly" things: Verbs
	$prio += 10 if $pair->{vnav} && scalar grep { !($_ ~~ @VERBMODIFIERS) } @mods;
	# silly things: affix inter marker
	$prio += 3 * scalar @mods if $pair->{eng} =~ /\(.*?affix inter marker.*?\)/ && scalar @mods;
	$prio += 5 * scalar @mods if $pair->{type} eq 'marker.' && scalar @mods;
	# silly things: pronouns.
	#~ $prio += scalar @mods if $pair->{eng} =~ /\(.*?pn.*?\)/ && scalar @mods;
	#~ print "Prio $prio for '$stripped' [@mods] ($pair->{nav} / ", $pair->{snav} || '', ")\n\n" if $DEBUG;
	return $prio;
}

sub advTranslateSentence {
	my ($db, $text) = @_;
	# The result.
	my @result;
	# We will have to "modify" it a bit.
	# Characters that are used to indicate NOOBISH behaviour are stirpped.
	$text =~ s/[<>\-.,:!?]//go;
	# Remove lines
	$text =~ s/[\r\n]+/ /go;
	$text =~ s/ {2,}/ /go;
	utf8::decode($text);
	# Split it into words
	my @swords = grep { $_ !~ /^ *$/ } split / /, $text;
	for my $word (@swords) {
		# In founds are arrayrefs
		# [ 
		#   SCALAR PRIORITY,
		#   HASHREF PAIR,
		#   ARRAYREF MODS,
		#   SCALAR FOUND WORD
		# ]
		my @found = ();
		my $rword = denavizes($word);
		# Check for default pairs.
		for my $pair (@{$db->{words}}) {
			# Normal
			if (lc $pair->{nav} eq lc $word) {
				push @found, [1, $pair, [], $word];
				# hello, si and sì, meaning TOTALLY DIFFERENT THINGS >:(
				next;
			}
		}
		
		my $rorgword = undef;
		# Check again using voodooo
		if (!scalar @found) {
			my @mods;			
			for my $pair (@{$db->{words}}) {
				if (!defined $rorgword) {
					@mods = ();
				}
				# Participle: Makes a verb to an adjective.
				if (!defined $rorgword && $pair->{vnav} && $word =~ /^(.*?|)(ke|)$pair->{vnav}(.*?|)$/i) {
					my ($pre, $neg, $infix1, $infix2, $infix0, $post) = ($1, $2, $4, $5, $3, $6);
					# wenn, und nur WENN infix1 = us
					# gibt es negative participle?
					if ($infix0 && ($infix0 eq 'us' || $infix0 eq 'awn') && !$infix1 && !$infix2) {
						# "cheat"
						$rorgword = $word;
						$word = $pre.$neg.$pair->{nav}.$post;
						push @mods, 'PART';
						#~ push @mods, 'NOT' if $neg;
						redo;
					}
				}
				
				my $stripped = '';
				if ($word =~ /$pair->{qnav}/i) {
					$stripped = advStripWordDownNew($word, $pair, \@mods) ;
				}
				
				if (scalar @mods) {
					# because we have to reset @mods between to words,
					# we have to use a copy when passing it as a reference
					my @a = @mods;
					if ($pair->{nav} ne $stripped) {
						push @a, '-PLEASEIGNOREME';
					}
					my $prio = calcPriorityForStripped($pair, $stripped, @a);
					push @found, [$prio, $pair, \@a, $word];
					@mods = ();
					next;
				} 
				
				if ($pair->{vnav} && $word =~ /^(ke|)$pair->{vnav}$/i) {
					my ($infix1, $infix2, $infix0, $neg, $infix0b, $infix1b, $infix2b) = ($3, $4, $2, $1, $5, $6, $7);
					$infix0 = $infix0b if defined $infix0b && !defined $infix0;
					$infix1 = $infix1b if defined $infix1b && !defined $infix1;
					$infix2 = $infix2b if defined $infix2b && !defined $infix2;
					$infix0 = '' if !defined $infix0;
					$infix1 = '' if !defined $infix1;
					$infix2 = '' if !defined $infix2;
					
					# NOW PUSH CART
					push @mods, 'NOT' if $neg;
					push @mods, 'VERB';
					
					if ($infix0) {
						if (!exists $INFIXES{$infix0}) {
							push @mods, "UNKNOWN0($infix0)";
						}
						else {
							push @mods, $INFIXES{$infix0}{sc};
						}
					}
					
					if ($infix1) {
						if (!exists $INFIXES{$infix1}) {
							push @mods, "UNKNOWN1($infix1)";
						}
						else {
							push @mods, $INFIXES{$infix1}{sc};
						}
					}
					
					if ($infix2) {
						if (!exists $INFIXES{$infix2}) {
							push @mods, "UNKNOWN2($infix2)";
						}
						else {
							push @mods, $INFIXES{$infix2}{sc};
						}
					}
					my @a = @mods;
					push @found, [0, $pair, \@a, $word];
				}
				
				if (!scalar @mods) {
					# please don't tell me it's lenited.
					# ay, me, mì can cause lenition. that doesn't matter anyway :-D
					if (!defined $rorgword && $pair->{lnav} && $word =~ /^(.*?|)$pair->{qlnav}(.*?|)$/i) {
						# ... redo.
						$rorgword = $word;
						$word = "$1$pair->{nav}$2";
						push @mods, 'LEN';
						redo;						
					}
					
					# Not found? Maybe the CONTRADICTION!
					if (!scalar @mods && !defined $rorgword && $pair->{snav} && $word =~ /^(.*?|)$pair->{snav}(.*?|)$/i) {
						my ($pre, $post) = ($1, $2);
						# ... redo
						$rorgword = $word;
						$word = "$1$pair->{nav}$2";
						push @mods, 'CONT';
						redo;
					}	
				}
				
				if (defined $rorgword) {
					$word = $rorgword;
					$rorgword = undef;
				}
			}
		}

		# It could be a number?
		if ($word =~ /$NUMBERREGEX/i && defined naviToNum($word)) {
			# Oh god. Check if it's a number.
			my $num = naviToNum($word);
			# G...rah?
			my $fakeword = {'nav' => $word, 'rnav' => $rword, 'eng' => $num, 'eeng' => $num, 'typeeng' => 'num.', 'type' => 'num.'};
			for my $lc (grep { $LANGUAGES{$_}{active} } keys %LANGUAGES) {
				$fakeword->{$lc} = $num;
				$fakeword->{"e$lc"} = $num;
			}
			print "THIS NUMBER IS REAL!\n";
			push @found, [1, $fakeword, [], $word];
		}
			
		if (!scalar @found) {
			push @result, [$word, {'nav' => $word, 'rnav' => $rword, 'eng' => undef}, []];
		} else {
			# sort.
			@found = sort { $a->[0] <=> $b->[0] } @found;
			# Ignore all founds that have the -PLEASEIGNOREME flag
			my $hasFound = 0;
			for my $findling (@found) {
				# brr. I want in array - there is ~~
				if (!('-PLEASEIGNOREME' ~~ @{$findling->[2]})) {
					my %pairz = %{$findling->[1]};
					@{$findling->[2]} = grep { $_ ne 'VERB' } @{$findling->[2]};
					push @result, [$findling->[3], \%pairz, $findling->[2]];
					$hasFound = 1;
					last;
				} else {
					@{$findling->[2]} = grep { $_ ne '-PLEASEIGNOREME' && $_ ne 'VERB' } @{$findling->[2]};
					my %pairz = %{$findling->[1]};
					$findling->[1] = \%pairz;
				}
			}
			if (!$hasFound) {
				$found[0][1]{eng} = undef;
				@{$found[0][2]} = grep { $_ ne 'VERB' } @{$found[0][2]};
				push @result, [$word, $found[0][1], []];
			}
		}
	}
	
	# Check if we can refine it again using ATTENTION WORDZ
	# This is bugged like hell and eats little children. err, I mean, it eats words.
	eval {
	for (my $i = 0; $i <= $#result; ++$i) {
		my $data = $result[$i];
		#~ print "Is $data->[1]{nav} dangerously?\n";
		if ($data->[1]{nav} ~~ @ATTENTIONWORDS) {
			#~ print "OH NO\nI HAVE TO PAY ATTENTION FOR $data->[1]{nav}\nHELP!\n";
			my @coulditreallybe = ();
			for my $paw (@LISTEDATTENTIONWORDS) {
				if ($paw->{nav} =~ /$data->[1]{qnav}/i) {
					# Is it at the end?
					my @spaff = split / /, $paw->{nav};										
					#~ print "Possible match: $paw->{nav} (", join('-', @spaff), ")\n";
					#~ print "Try $paw->{nav} =~ /$data->[1]{qnav}\$/i\n";
					if ($paw->{nav} =~ / $data->[1]{qnav}$/i) {
						# check for EACH word before if it does match
						my $j = $i;
						my $isit = 0;
						my @pwzzz = ([$result[$i][0], $result[$i][2]]);
						for my $mustmatch (@spaff) {
							#~ print "Try $mustmatch against $result[$j][1]{nav}.\n";
							last if --$j < 0;
							if ($mustmatch eq $result[$j][1]{nav}) {
								$isit++;
								push @pwzzz, [$result[$j][0], $result[$j][2]];
							}
						}
						if ($isit != length @spaff) {
							#~ print "It can't be $paw->{nav} ($isit)~1 ($#spaff)\n";
							next;
						}
						# It is it. brr.
						#~ print "IT IS $paw->{nav}~1 ($isit == $#spaff)!!!\n";
						#~ print "cut off it is kind of ", ::Dumper([map { @{$_->[1]} } @pwzzz]);
						#~ print "(because of ", ::Dumper(\@pwzzz), ")\n";						
						my $miximaxi = [join(' ', map { $_->[0] } @pwzzz), $paw, [map { @{$_->[1]} } @pwzzz]];
						my @tres = (@result[0..$j], $miximaxi);
						push @tres, @result[$i+1..$#result] if ($i+1 <= $#result);
						@result = @tres;
						last;
					}
					elsif ($paw->{nav} =~ /^$data->[1]{qnav} /i) {
						# check for EACH word before if it does match
						my $j = $i;
						my $isit = 0;
						my @pwzzz = ([$result[$i][0], $result[$i][2]]);
						for my $mustmatch (@spaff) {
							#~ print "Try $mustmatch against $result[$j][1]{nav}~2\n";
							last if ++$j > $#result;
							if ($mustmatch eq $result[$j][1]{nav}) {
								$isit++;
								push @pwzzz, [$result[$j][0], $result[$j][2]];
							}
						}
						if ($isit != length @spaff) {
							#~ print "It can't be $paw->{nav} ($isit)~2 ($#spaff)\n";
							next;
						}
						# It is it. brr.
						#~ my $combo = join(' ', map { $_[0] } @pwzzz);
						#~ print "IT IS $paw->{nav}~2 ($isit == $#spaff)!!!\n";
						#~ print "cut off it is kind of ", ::Dumper([map { @{$_->[1]} } @pwzzz]);
						#~ print "(because of ", ::Dumper(\@pwzzz), ")\n";						
						my $miximaxi = [join(' ', map { $_->[0] } @pwzzz), $paw, [map { @{$_->[1]} } @pwzzz]];
						my @tres = (@result[0..$i], $miximaxi);
						push @tres, @result[$j+1..$#result] if ($j+1 <= $#result);
						@result = @tres;
						last;
					}
				}
			}
			#~ print "No attention anymore!\n";
		}
		#~ print "Next word plz\n";
	}
	};
	if ($@) {
		print "ERROR!!!! $@\n";
	}
	#~ print "Before it went:\n";
	#~ print ::Dumper(\@result);
	return @result;
}

sub tipaToPerl {
	my ($text) = @_;
	utf8::encode($text);
	$text =~ s/N/Å‹/go;
	$text =~ s/R/É¾/go;
	$text =~ s/P/Ê”/go;
	$text =~ s/U/ÊŠ/go;
	$text =~ s/E/É›/go;
	$text =~ s/I/Éª/go;
	$text =~ s/\\textcorner ?/Ìš/go;
	$text =~ s/\\textprimstress ?/Ëˆ/go;
	$text =~ s/\\textsecstress ?/ËŒ/go;
	$text =~ s/\\textsyllabic{([^}]*)}/$1Ì£/go;
	$text =~ s/\\texttslig ?/Ê¦/go;
	$text =~ s/\$\\cdot\$/Â·/go;
	$text =~ s/\\t\{ts\}/tÍ¡s/go;
	$text =~ s/\\ / /go;
	utf8::decode($text);
	return $text;
}

sub leniteWord {
	my ($word) = @_;
	# If it's not the easy-lenite-word it's may the evil-lenite-word.
	if ($word !~ s/^([ktpKTP])x/$1/o && $word !~ s/^[Tt]s/s/o) {
		$word =~ s/^([ktpKTP'])/my $a = $1; $a =~ tr!ktpKTP'!hsfHSF!d; $a;/ie;
	}
	return $word;
}
1;