# Haver::Client::UserList
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
package Haver::Client::UserList;
use strict;
use warnings;

use Haver::Preprocessor;
use Haver::Base;
use base 'Haver::Base';
use overload (
	'@{}' => 'as_array',
	fallback => 1,
);

our $VERSION = '0.01';

sub initialize {
	my ($me) = @_;

	$me->clear;
}

sub add {
	my ($me, $uid, $uinfo) = @_;

	unless ($me->has($uid)) {
		my $i = push (@{$me->{user_list}}, $uid);
		$me->{user_index}{$uid} = $i - 1;
		$me->{user_info}{$uid}  = $uinfo;
		$me->on_add($uid);
	}
	DUMP: $me;
}

sub on_add {
	my ($me, $uid) = @_;
	if ($me->{on_add}) {
		$me->{on_add}->($me, $uid);
	}
}

sub user_info {
	my ($me) = @_;
	my $a = $me->{user_list};

	return wantarray ? @$a : [ @$a ];
}

sub as_array {
	[ @{$_[0]{user_list}} ];
}

sub remove {
	my ($me, $uid) = @_;

	my @users;
	my $info = delete $me->{user_info}{$uid};
	$me->{user_index} = {};
	my $i = 0;
	
	foreach my $u (@{$me->{user_list}}) {
		next if $uid eq $u;
		$me->{user_index}{$u} = $i++;
		push(@users, $u);
	}
	$me->{user_list} = \@users;
	
	$me->on_remove($uid, $info);
}

sub on_remove {
	my ($me, $uid, $info) = @_;
	if ($me->{on_remove}) {
		$me->{on_remove}->($me, $uid, $info);
	}
}

sub has {
	my ($me, $uid) = @_;
	return exists $me->{user_info}{$uid};
}

sub fetch_info {
	my ($me, $uid) = @_;
	return $me->{user_info}{$uid};
}

sub index {
	my ($me, $uid) = @_;
	return $me->{user_index}{$uid};
}


sub clear {
	my ($me) = @_;
	$me->{user_info}      = {};
	$me->{user_index}     = {};
	$me->{user_list}      = [];

}

1;

