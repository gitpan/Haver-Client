package Haver::Client;

use 5.008002;
use strict;
use warnings;

use POE qw(Wheel::ReadWrite
	   Wheel::SocketFactory);
use Haver::Protocol::Filter;
use Carp;
use Digest::SHA1 qw(sha1_base64);
use Data::Dumper;
require Exporter;

our $VERSION = '0.04';

### SETUP

sub new ($$) {
    my ($class, $alias) = @_;
    carp "Can't call ->new on a ".(ref $class)." instance" if ref $class;
    carp "Haver::Client can't be subclassed" if($class ne __PACKAGE__);
    POE::Session->create(package_states =>
			 [ __PACKAGE__,
			   [qw{
			       _start

				   register
				   unregister
				   dispatch

				   connect
				   connected
				   connectfail

				   input
				   send
				   net_error

				   destroy
				   disconnect
				   force_close
				   flushed
				   cleanup
				   _stop

				   login
				   join
				   part
				   msg
				   pmsg
				   act
				   pact
				   users

				   event_WANT
				   event_ACCEPT
				   event_REJECT
				   event_PING
				   event_CLOSE
				   
				   event_JOIN
				   event_PART
				   event_MSG
				   event_PMSG
				   event_ACT
				   event_PACT
				   event_USERS
				   event_BYE
				   event_QUIT

				   _default

			       }]],
			 args => [$alias]
			 );
    return 1;
}

sub _start {
    my ($kernel, $heap, $session, $alias) = @_[KERNEL,HEAP,SESSION,ARG0];
    $kernel->alias_set($alias);
    %$heap = (alias => $alias,
	      registrations => {}
	      );
}

### DISPATCH

sub register {
    my ($kernel, $heap, $sender, @events) = @_[KERNEL,HEAP,SENDER,ARG0..$#_];
    for(@events) {
	if(!exists $heap->{registrations}->{$_}->{$sender->ID}) {
	    $heap->{registrations}->{$_}->{$sender->ID} = $heap->{alias} . "##$_";
	    $kernel->refcount_increment($sender->ID, $heap->{alias} . "##$_");
	}
    }
}

sub unregister {
    my ($kernel, $heap, $sender, @events) = @_[KERNEL,HEAP,SENDER,ARG0..$#_];
    for(@events) {
	if(exists $heap->{registrations}->{$_}->{$sender->ID}) {
	    delete $heap->{registrations}->{$_}->{$sender->ID};
	    $kernel->refcount_decrement($sender->ID, $heap->{alias} . "##$_");
	}
    }
}

sub dispatch {
    my ($kernel, $heap, $event, @args) = @_[KERNEL,HEAP,ARG0..$#_];
    my %targets = (map { $_ => 1 } (keys(%{$heap->{registrations}->{$event}}),
				    keys(%{$heap->{registrations}->{all}})));
    $kernel->post($_, "haver_$event", @args) for keys %targets;
}

### CONNECT

sub connect {
    my ($kernel, $heap, %args) = @_[KERNEL,HEAP,ARG0..$#_];
# XXX: Better error reporting
    croak "Missing required parameter Host" unless exists $args{Host};
    if(exists $heap->{conn}) {
	$kernel->yield('disconnect') unless exists $heap->{pending_connection};
	$heap->{pending_connection} = [%args];
	return;
    }
    $heap->{UID} = $args{UID};
    $args{Port} ||= 7070;
    $heap->{connect_wheel} =
	POE::Wheel::SocketFactory->new(
				       RemoteAddress => $args{Host},
				       RemotePort => $args{Port},
				       SuccessEvent => 'connected',
				       FailureEvent => 'connectfail'
				       );
}

sub connected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    my ($handle, $id) = @_[ARG0,ARG3];
    if(!exists $heap->{connect_wheel} ||
       $heap->{connect_wheel}->ID() != $id){
	close $handle;
	return;
    }
    $heap->{conn} =
	POE::Wheel::ReadWrite->new(
				   Handle => $handle,
				   Driver => POE::Driver::SysRW->new(),
				   Filter => Haver::Protocol::Filter->new(),
				   InputEvent => 'input',
				   FlushedEvent => 'flushed',
				   ErrorEvent => 'net_error'
				   );
    delete $heap->{connect_wheel};
    $heap->{flushed} = 1;
    $kernel->yield(dispatch => 'connected');
}

sub connectfail {
    my ($kernel, $heap, $enum, $estr) = @_[KERNEL,HEAP,ARG1,ARG2];
    $kernel->yield(dispatch => connect_fail => $enum, $estr);
    delete $heap->{connect_wheel};
}

sub net_error {
    my ($kernel, $heap, $enum, $estr) = @_[KERNEL,HEAP,ARG1,ARG2];
    $kernel->yield(dispatch => disconnected => $enum, $estr);
    $kernel->yield('cleanup');
}

### IO

sub input {
    my ($kernel, $event) = @_[KERNEL,ARG0];
    print STDERR "S: ", join("\t", @$event), "\n";
    my $ename = shift @$event;
    $kernel->yield("event_$ename", @$event);
    $kernel->yield('dispatch', 'raw', $ename, @$event);
}

sub send {
    my ($kernel, $heap, @message) = @_[KERNEL,HEAP,ARG0..$#_];
    if($heap->{want}) {
	if(($heap->{want} ne uc $message[0]) &&
	   ((uc $message[0] ne 'CANT') || ($message[1] ne $heap->{want}))) {
	    print STDERR "(blocked) C: ", join("\t", @message), "\n";
	    push @{$heap->{messageq} ||= []}, [@message];
	    return;
	}
	delete $heap->{want};
    }
    print STDERR "C: ", join("\t", @message), "\n";
    $heap->{conn}->put(\@message);
    if(exists $heap->{messageq}) {
	for (@{$heap->{messageq}}) {
	    $kernel->yield(send => @$_);
	}
	delete $heap->{messageq};
    }
    $heap->{flushed} = 0;
}

### SERVER EVENTS

# XXX: Make a more extensible WANT system later
sub event_WANT {

    my ($kernel, $heap, $wanted, $arg) = @_[KERNEL,HEAP,ARG0,ARG1];
    $wanted = uc $wanted;
    $heap->{want} = $wanted;
    my %wants =
	(
	 VERSION => sub {
	     $kernel->yield(send => VERSION => "Haver::Client/$VERSION");
	 },
	 UID => sub {
	     if(defined $heap->{UID}) {
		 $kernel->yield(send => UID => $heap->{UID});
	     }else{
		 $kernel->yield(dispatch => 'login_request');
	     }
	 },
	 PASS => sub {
	     if(defined $heap->{PASS}) {
		 $kernel->yield(send => PASS =>
				sha1_base64(sha1_base64($heap->{PASS}) .
					    $arg));
	     }else{
		 $kernel->yield(dispatch => 'login_request');
	     }
	 }
	 );
    $heap->{want} = $wanted;
    if(exists $wants{$wanted}) {
	$wants{$wanted}();
    }else{
	$kernel->yield(send => CANT => $wanted);
    }
}

sub event_ACCEPT {
    my ($kernel, $heap) = @_[KERNEL,HEAP];
    $heap->{logged_in} = 1;
    $kernel->yield(dispatch => 'login');
}

sub event_REJECT {
    my ($kernel, $heap, $etag, $estr) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield(dispatch => login_fail => $etag, $estr);
}

sub event_PING {
    my ($kernel, $heap, @junk) = @_[KERNEL,HEAP,ARG0..$#_];
    $kernel->yield(send => 'PONG', @junk);
}

sub event_CLOSE {
    my ($kernel, $heap, $etyp, $estr) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield(dispatch => close => $etyp, $estr);
}

sub event_JOIN {
    my ($kernel, $heap, $cid, $uid) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield('dispatch', ($uid eq '.' ||
				$uid eq $heap->{UID}) ? 'joined' : 'join',
		   $cid, $uid);
}

sub event_PART {
    my ($kernel, $heap, $cid, $uid) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield('dispatch', ($uid eq '.' ||
				$uid eq $heap->{UID}) ? 'parted' : 'part',
		   $cid, $uid);
}

sub event_MSG {
    my ($kernel, $heap, $cid, $uid, $text) = @_[KERNEL,HEAP,ARG0..ARG2];
    $kernel->yield(dispatch => public => $cid, $uid, $text);
}

sub event_ACT {
    my ($kernel, $heap, $cid, $uid, $text) = @_[KERNEL,HEAP,ARG0..ARG2];
    $kernel->yield(dispatch => pubact => $cid, $uid, $text);
}

sub event_PMSG {
    my ($kernel, $heap, $uid, $text) = @_[KERNEL,HEAP,ARG0..ARG1];
    $kernel->yield(dispatch => private => $uid, $text);
}

sub event_PACT {
    my ($kernel, $heap, $uid, $text) = @_[KERNEL,HEAP,ARG0..ARG1];
    $kernel->yield(dispatch => privact => $uid, $text);
}

sub event_USERS {
    my ($kernel, $heap, $where, @who) = @_[KERNEL,HEAP,ARG0..$#_];
    $kernel->yield(dispatch => users => $where, @who);
}

sub event_BYE {
    my ($kernel, $heap, $why) = @_[KERNEL,HEAP,ARG0];
    $kernel->yield(dispatch => bye => $why);
}

sub event_QUIT {
    my ($kernel, $heap, $who, $why) = @_[KERNEL,HEAP,ARG0,ARG1];
    if($who eq '.') {
	# Work around nonconformant servers
	$kernel->yield(dispatch => bye => $why);
	return;
    }
    $kernel->yield(dispatch => quit => $who, $why);
}

### CLIENT EVENTS

sub login {
    my ($kernel, $heap, $uid, $pass) = @_[KERNEL,HEAP,ARG0,ARG1];
    $heap->{UID} = $uid;
    $heap->{PASS} = $pass;
    if($heap->{want}) {
	if($heap->{want} eq 'UID') {
	    $kernel->yield(send => UID => $heap->{UID});
	    if(!defined $uid) {
		# oops...
		delete $heap->{UID};
		delete $heap->{PASS};
		$kernel->yield(dispatch => login_fail => 'UNDEF_UID',
			       'Internal client error: UID is undefined');
		return;
	    }
	}elsif($heap->{want} eq 'PASS') {
	    if(defined $pass) {
		$kernel->yield(send => PASS => $pass);
	    }else{
		$kernel->yield(send => CANT => 'PASS');
	    }
	}
    }
}

sub join {
    my ($kernel, $heap, $where) = @_[KERNEL,HEAP,ARG0];
    $kernel->yield(send => 'JOIN', $where);
}

sub part {
    my ($kernel, $heap, $where) = @_[KERNEL,HEAP,ARG0];
    $kernel->yield(send => 'PART', $where);
}

sub msg {
    my ($kernel, $heap, $where, $message) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield(send => 'MSG', $where, $message);
}

sub pmsg {
    my ($kernel, $heap, $where, $message) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield(send => 'PMSG', $where, $message);
}

sub act {
    my ($kernel, $heap, $where, $message) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield(send => 'ACT', $where, $message);
}

sub pact {
    my ($kernel, $heap, $where, $message) = @_[KERNEL,HEAP,ARG0,ARG1];
    $kernel->yield(send => 'PACT', $where, $message);
}

sub users {
    my ($kernel, $heap, $where) = @_[KERNEL,HEAP,ARG0];
    $kernel->yield(send => 'USERS', $where);
}

### SHUTDOWN

sub disconnect {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    return if $heap->{closing};
    $heap->{closing} = 1;
    $kernel->yield(send => 'QUIT');
    $kernel->delay(force_close => 5);
}

sub force_close {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    return if $heap->{closing} == 3;
    if($heap->{closing} == 2 || $heap->{flushed}){ # Flushed or flush timeout
	$kernel->yield('cleanup');
	$kernel->yield(dispatch => disconnected => -1, 'Disconnected');
	$kernel->delay('force_close');
	$heap->{closing} = 3;
	return;
    }
    $heap->{closing} = 2;
    $kernel->delay('force_close' => 5);
}

sub flushed {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    if(defined $heap->{closing} && $heap->{closing} == 2) {
	$kernel->yield('force_close');
    }
    $heap->{flushed} = 1;
}

sub cleanup {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    delete $heap->{$_} for qw(conn flushed closing UID PASS);
    $kernel->delay('force_close');
    if($heap->{destroy_pending}) {
	$kernel->yield('destroy');
    }elsif(exists $heap->{pending_connection}) {
	$kernel->yield('connect' => @{$heap->{pending_connection}});
	delete $heap->{pending_connection};
    }
}

sub destroy {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    print STDERR "Destroying.\n";
    if(exists $heap->{conn}){
	$heap->{destroy_pending} = 1;
	$kernel->yield('disconnect');
	return;
    }
    $kernel->alias_remove($heap->{alias});
}

sub _stop {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    foreach my $evt (keys %{$heap->{registrations}}) {
	my $ehash = $heap->{registrations}->{$evt};
	foreach my $session (keys %$ehash) {
	    my $refcount = $ehash->{$session};
	    $kernel->refcount_decrement($session, $refcount);
	}
    }
}

sub _default {
    my ( $kernel, $state, $event, $args, $heap ) = @_[ KERNEL, STATE, ARG0, ARG1, HEAP ];
    $args ||= [];    # Prevents uninitialized-value warnings.
    print STDERR "default: $state = $event. Args:\n".Dumper $args;
    return 0;
}


1;
__END__

=head1 NAME

Haver::Client - Namespace for client stuff.

=head1 SYNOPSIS

  use Haver::Client;

=head1 DESCRIPTION

This module is nought but a place holder.

=head1 SEE ALSO

L<http://wiki.chani3.com/wiki/ProjectHaver/>

=head1 AUTHOR

Dylan William Hardison, E<lt>dylanwh@tampabay.rr.comE<gt> and
Bryan Donlan, E<lt>bdonlan@bd-home-comp.no-ip.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Bryan Donlan, Dylan William Hardison

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this module; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


=cut
