#!/usr/bin/perl
# eanaeltuyaevrrtep.pl, part of Eana Eltu by Tobias Jaeggi (Tuiq, tuiq at clonk2c dot ch), Richard Littauer (Taronyu, richard@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ).
# The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use DBI;
use Time::Format;

use SpeakNavi;
use JSON;
use EEConfig;

# for the unix socket.
my $SERVER_FILE = $EEConfig::cfg->{serverfile};

# Loading keys. They are usually MD5 hashes of a silly sentence, but can be anything.
my @KEYS;
{
	open(my $FH, '.keys');
	@KEYS = <$FH>;
	close $FH;
};

# MySQL connection
my $DATABASE = $EEConfig::cfg->{databaseName};
my $USER = $EEConfig::cfg->{databaseUser};
my $PASSWORD = $EEConfig::cfg->{databasePassword};

my @LANGUAGES;
my %LCS;

sub logSth {
	my ($text) = @_;
	print $time{'hh:mm:ss'}, ': ', $text, "\n";
}

sub warnSth {
	my ($text) = @_;
	warn $time{'hh:mm:ss'}, ': ', $text, "\n";
}

# Starting.

logSth("Starting server...");

#~ my $sock = IO::Socket::INET->new(
		#~ LocalPort => $SERVER_PORT,
		#~ Proto => 'udp')
	#~ or die "Couldn't start server on port $SERVER_PORT: $@\n";

# UNIX sockets.
unlink $SERVER_FILE;

my $sock = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Local => $SERVER_FILE,
		Listen => SOMAXCONN, # max connections?
) or die "Error creating socket: $!\n";

# chmod
chmod 0777, $SERVER_FILE;

my $select = IO::Select->new($sock);

logSth("Server started.");

logSth("Loading database...");

my $ydb;
my $lookupSth;
my $translateSth;

sub initDatabase {
	logSth("(Re-)Initialize Database");
	logSth("Opening the MySQL Database.");
	$ydb = SpeakNavi->openMySQLDatabase($DATABASE, $USER, $PASSWORD);
	logSth("Opened.");
	logSth("Prepare queries.");
	$lookupSth = $ydb->{dbh}->prepare('INSERT INTO wordLookup (text, lc, time) VALUES (?, ?, ?)');
	$translateSth = $ydb->{dbh}->prepare('INSERT INTO naviSentences (text, time) VALUES (?, ?)');
	logSth("Prepared.");
	logSth("Setting languages...");
	@LANGUAGES = grep { $SpeakNavi::LANGUAGES{$_}{active} } keys %SpeakNavi::LANGUAGES;
	push @LANGUAGES, 'nav';
	logSth("Supporting @LANGUAGES");
	%LCS;
	$LCS{$_} = $SpeakNavi::LANGUAGES{$_} for (@LANGUAGES);
	logSth("Check: " . join(' ', keys %LCS));
}

initDatabase();

logSth("Loaded.\n");

logSth("Hooking SIGINT.");
$SIG{'INT'} = sub {
	logSth("SIGINT");
	close $sock;
	unlink $SERVER_FILE;
	exit;
};

logSth("Hooked.");

my %connections;

sub sendAnswer {
	my ($s, %h) = @_;
	my $j = to_json(\%h);
	utf8::encode($j);
	$s->send(pack "L", length $j);
	$s->send($j);
	logSth("Sending something to $s (" . (length $j) . ")");
}

logSth("Ready.");

# This could be improved?
while ((my @readready = $select->can_read(scalar keys %connections ? 30 : undef)) || scalar keys %connections) {
	logSth("LoopStart");
	# Check if we are still connected to the database.
	initDatabase if !$ydb->{dbh}->ping;
	# Otherwise it's getting embarassing.
	foreach my $fh (@readready) {
		logSth("Inner Loop Start: $fh");
		if ($fh == $sock) {
			my $new = $sock->accept();
			$select->add($new);
			$connections{$new} = {t => time+30, p => 0};
			logSth("New connection");

		} else {
			my $msg;
			$fh->recv($msg, 32768);
			
			my $close = 1;
			# $client is new connection
			eval {
				die 'Empty message: ' . Dumper($msg) if (!$msg);
				utf8::decode($msg);
				my $data = from_json($msg);
				my $req;
				if (!exists $data->{request} || $data->{request} !~ /^(translate|lookup|num|peristent|lcs|refresh|getemall)$/) {
					logSth("Invalid request field");
					sendAnswer($fh, status => 'Failure', message => "Invalid request field ($data->{request})");
					return 1;
				} else {
					$req = $1;
				}
	
				if (!exists $data->{key} || !($data->{key} ~~ @KEYS)) {
					logSth("Invalid key");
					sendAnswer($fh, status => 'Failure', message => 'Invalid key');
					return 1;
				}
		
				if ($data->{request} ne 'peristent' && $data->{request} ne 'lcs' && $data->{request} ne 'refresh' && $data->{request} ne 'getemall' && (!exists $data->{data} || !$data->{data})) {
					logSth("Invalid data");
					sendAnswer($fh, status => 'Failure', message => 'Invalid data');
					return 1;
				}
				
				if ($req eq 'peristent') {
					# NA GUT DANN HALt
					sendAnswer($fh, status => 'Success');
					$connections{$fh}{t} = time+86400;
					$connections{$fh}{p} = 1;
					logSth("Peristance for $fh granted.");
					$close = 0;
					return 1;
				}
				
				# Translate?
				elsif ($req eq 'translate') {
					logSth("Translating");
					utf8::decode($data->{data});
					$translateSth->execute($data->{data}, time);
					my @trans = grep { defined @{$_}[0] } $ydb->advTranslateSentence($data->{data});
					my @rtrans;
					for my $d (@trans) {
						my %er = %{$d->[1]};
						delete $er{vnav};
						delete $er{qnav};
						delete $er{qlnav};
						delete $er{ipa};
						delete $er{id};
						for my $lc (@LANGUAGES) {
							delete $er{"r$lc"};
						}
						$er{rmods} = join ' ', map { exists $SpeakNavi::SHORTTERMS{$_} ? $SpeakNavi::SHORTTERMS{$_}[2] : sprintf $SpeakNavi::SHORTTERMS{UNKNOWN}[2], $_; } @{$d->[2]};
						for my $lc (@LANGUAGES) {
							next if $lc eq 'eng' || $lc eq 'nav';
							$er{"rmods$lc"} = join(' ', map { exists $SpeakNavi::SHORTTERMS{$_}[3]{"desc$lc"} ? $SpeakNavi::SHORTTERMS{$_}[3]{"desc$lc"} : sprintf $SpeakNavi::SHORTTERMS{UNKNOWN}[2], $_;  } @{$d->[2]}
							);
						}
						@{$er{smods}} = map { exists $SpeakNavi::SHORTTERMS{$_} ? $SpeakNavi::SHORTTERMS{$_}[0] : $SpeakNavi::SHORTTERMS{UNKNOWN}[0] } @{$d->[2]};
						@{$er{pmods}} = map { exists $SpeakNavi::SHORTTERMS{$_} ? $SpeakNavi::SHORTTERMS{$_}[1] : $SpeakNavi::SHORTTERMS{UNKNOWN}[1] } @{$d->[2]};
						# Warum genau kopiere ich das hier?
						push @rtrans, [$d->[0], \%er, $d->[2]];
					}
					sendAnswer($fh, status => 'Success', data => \@rtrans, lcs => \@LANGUAGES);
					return 1;
				}
				# Lookup?
				elsif ($req eq 'lookup') {
					logSth("Looking up");
					if (!exists $data->{langs} || !scalar @{$data->{langs}}) {
						sendAnswer($fh, status => 'Failure', message => 'Invalid languages');
						return 1;
					}
					
					if (!exists $data->{exact} || !defined $data->{exact}) {
						sendAnswer($fh, status => 'Failure', message => 'Invalid bool exact');
						return 1;
					}
					
					# Look up EVRY language
					for my $lc (@{$data->{langs}}) {
						if (!($lc ~~ @LANGUAGES)) {
							sendAnswer($fh, status => 'Failure', message => 'Invalid languages ('.$lc.')');
							return 1;
						}
					}
					
					my $exact = 0;
					$exact = int($data->{exact}) || $data->{exact} =~ /^(true|yes)$/;
					utf8::decode($data->{data});
					$lookupSth->execute($data->{data}, join(' ', @{$data->{langs}}), time);
					my @trans = $ydb->advFindTranslations($data->{data}, $data->{langs}, $exact);
					my @rtrans;
					# Verfeiern
					for my $d (@trans) {
						my %er = %{$d->[0]};
						my $e = \%er;
						delete $er{vnav};
						delete $er{qnav};
						delete $er{qlnav};
						utf8::decode($er{ipa});
						#~ delete $er{ipa};
						delete $er{id};
						for my $lc (@LANGUAGES) {
							delete $e->{"r$lc"};
						}
						push @rtrans, [$e, $d->[1]];
					}
					sendAnswer($fh, status => 'Success', data => \@rtrans, lcs => \@LANGUAGES);
					return 1;
				}
				# Numz
				elsif ($req eq 'num') {
					logSth("Numerics");
					sendAnswer($fh, status => 'Success', data => SpeakNavi::numToNavi($data->{data}));
					return 1;
				}
				# Lcs
				elsif ($req eq 'lcs') {
					logSth("LCS");
					sendAnswer($fh, status => 'Success', data => \%LCS);
					# Allow more requests afterwards.
					$close = 0;
					return 1;
				}
				# refresh
				elsif ($req eq 'refresh') {
					logSth("Forced refreshing...");
					# ASD
					$ydb->refreshMySQLDatabase();
					sendAnswer($fh, status => 'Success');
					logSth("Refreshed.");
					$close = 0;
					return 1;
				}
				# SQL creation only. huge amount of data.
				elsif ($req eq 'getemall') {
					logSth("Request to get all data");
					my @result;
					for my $w (@{$ydb->{words}}) {
						my %wr = %$w;
						delete $wr{vnav};
						delete $wr{qnav};
						delete $wr{qlnav};
						for my $lc (@LANGUAGES) {
							delete $wr{"r$lc"};
							delete $wr{"e$lc"};
						}
						push @result, \%wr;
					}
					sendAnswer($fh, status => 'Success', data => \@result);
					logSth("Sent all data.");
					$close = 1;
					return 1;
				}
				# DIE
				else {
					sendAnswer($fh, status => 'Failure', message => 'Invalid request');
					return 1;
				}
				# Mirror
				sendAnswer($fh, status => 'Failure', 'message' => "Hurr. Something went really wrong.");
				logSth("Something went really wrong when parsing the request '$req'");
				return 1;
			};
			
			if ($@) {
				warnSth("Error parsing data: $@");
				if ($fh && $fh->connected) {
					sendAnswer($fh, status => 'Failure', message => 'Malformed query or internal error');
					delete $connections{$fh};
					$select->remove($fh);
					$fh = undef;
				}
				#~ $fh->send(to_json({status => 'Failure', message => 'Malformed query'}));
			}
			
			next if !$close || (defined $fh && exists $connections{$fh} && $connections{$fh}{p}); # peristente verbindungen
			if (defined $fh) {
				logSth("Disconnecting $fh due to close=1");
				delete $connections{$fh};
				$select->remove($fh);
				$fh->close;
				$fh = undef;
			}
			else {
				logSth("Disconnecting undefined socket");
			}
		}
		logSth("Handled.");
	}
	
	logSth("DC Loop Start");
	# Old things get out.
	while (my ($fh, $args) = each %connections) {
		next if $args->{t} > time;
		logSth("Disconnecting $fh\n");
		$select->remove($fh);
		delete $connections{$fh};
		close $fh;
	}
	logSth("DC Loop End");
	logSth("End Loop\n");
	@readready = ();
}

logSth("It's not, it's not shutting down!");
close $sock;