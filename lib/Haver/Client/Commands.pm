# Haver::Client::Commands -- deal with /commands.
# 
# Copyright (C) 2004 Bryan Donlan, Dylan William Hardison.
# 
# This module is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This module is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this module; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
package Haver::Client::Commands;
use strict;
use warnings;

use Text::ParseWords (); # we use parse_line.

use Haver::Base;
use base 'Haver::Base';

our $VERSION = '0.01';

sub initialize {
	my ($me) = @_;
	
	$me->{chars}       ||= '/.';
	$me->{default_cmd} ||= 'say';
}


sub invoke {
	my ($me, $s) = @_;
	my ($cmd, @args) = $me->parse($s);
	my $method = "do_$cmd";
	my $obj = $me->{invoke} || $me;
	
	if ($obj->can($method)) {
		$obj->$method(@args);
	} else {
		$obj->default_do($cmd, @args);
	}
}

sub parse {
	my ($me, $s) = @_;
	my $c = quotemeta $me->{chars};
	my ($cmd, $arg);
	
	if ($s =~ /^[$c] (\w+) (?:\s*) (.+) $/x) {
		$cmd = $1;
		$arg = $2;
	} else {
		$cmd = $me->{default_cmd};
		$arg = $s;
	}
	
	if (my $code = $me->can("parse_$cmd")) {
		return $code->($me, $cmd, $arg);
	} else {
		return $me->default_parse($cmd, $arg);
	}
}

sub default_do {
	my ($me, $cmd, @args) = @_;
	die "You should at least overload the default_do method!";
}

sub default_parse {
	my ($me, $cmd, $arg) = @_;
	return ($cmd, $arg);
}

sub parse_raw {
	my ($me, $cmd, $arg) = @_;
	my @args = grep(defined, Text::ParseWords::parse_line(qr/\s+/, 0, $arg));
	return ($cmd, @args);
}



1;

