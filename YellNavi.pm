# YellNavi.pm, part of Eana Eltu by Tobias Jaeggi (Tuiq, tuiq at clonk2c dot ch), Richard Littauer (Taronyu, richard@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ).
# The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .

use strict;
use warnings;

use IO::Socket;

use JSON;
use List::Util qw(min max);

package YellNavi;

sub new {
	my ($self, %paras) = @_;
	my $ref = {file => $paras{file}, key => $paras{key}, sock => undef, peristent => 0, lastError => undef};
	bless $ref;
}

sub connect {
	my ($yn) = @_;
	return 1 if $yn->available;
	$yn->{sock} = IO::Socket::UNIX->new(Peer => $yn->{file});
	if ($yn->{peristent}) {
		$yn->{peristent} = 0;
		$yn->askPeristentMode;
	}
	my $ail = $yn->available;
	return $ail;
}

sub askTranslation {
	my ($yn, $input) = @_;
	my $result = $yn->send(request => 'translate', data => $input);
	if (!$result || $result->{status} ne 'Success') {
		$yn->{lastError} = $result->{message} if exists $result->{message};
		return undef;
	}
	return $result->{data};
}

sub askLookup {
	my ($yn, $input, $languages, $exact) = @_;
	my $result = $yn->send(request => 'lookup', data => $input, langs => $languages, exact => $exact);
	if (!$result || $result->{status} ne 'Success') {
		$yn->{lastError} = $result->{message} if exists $result->{message};
		return undef;
	}
	return $result->{data};
}

sub askNum {
	my ($yn, $input) = @_;
	my $result = $yn->send(request => 'num', data => $input);
	if (!$result || $result->{status} ne 'Success') {
		$yn->{lastError} = $result->{message} if exists $result->{message};
		return undef;
	}
	return $result->{data};
}

sub askPeristentMode {
	my ($yn) = @_;
	return if $yn->{peristent};
	$yn->{peristent} = 1;
	return ($yn->send(request => 'peristent'))->{status} eq 'Success';
}

sub askLanguages {
	my ($yn) = @_;
	my $result = $yn->send(request => 'lcs');
	if (!$result || $result->{status} ne 'Success') {
		$yn->{lastError} = $result->{message} if exists $result->{message};
		return undef;
	}
	return $result->{data};
}

sub askRefresh {
	my ($yn) = @_;
	my $result = $yn->send(request => 'refresh');
	if (!$result || $result->{status} ne 'Success') {
		$yn->{lastError} = $result->{message} if exists $result->{message};
		return undef;
	}
	return 1;
}

sub askAllData {
	my ($yn) = @_;
	my $result = $yn->send(request => 'getemall');
	if (!$result || $result->{status} ne 'Success') {
		$yn->{lastError} = $result->{message} if exists $result->{message};
		return undef;
	}
	return $result->{data};
}

sub available {
	my ($yn) = @_;
	return $yn->{sock} && $yn->{sock}->connected;
}

sub send {
	my ($yn, %paras) = @_;
	return undef if !$yn->{sock};
	$paras{key} = $yn->{key};
	my $json = JSON::to_json(\%paras);
	utf8::encode($json);
	$yn->{sock}->send($json);
	return $yn->recv;
}

sub recv {
	my ($yn) = @_;
	return undef if !$yn->{sock};
	my $data;
	my $msg = '';
	eval {
		# Länge
		my $l;
		$yn->{sock}->recv($l, 4) or die 'Connection closed';
		die 'No length received' if (!$l);
		$l = unpack("L", $l);
		my $r = 0;
		my $buf;
		while ($l > $r) {
			$yn->{sock}->recv($buf, 8096);
			$r += length $buf;
			$msg .= $buf;
		}
		utf8::decode($msg);		
		$data = JSON::from_json($msg);
	};
	if ($@) {
		$yn->{lastError} = "recv: $@ with message $msg";
		return undef;
	}
	return $data;
}

1;