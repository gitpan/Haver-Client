#!/usr/bin/perl
# $Header: /cvsroot/haver/haver/client/bin/haver-tk-2.pl,v 1.7 2004/02/22 03:47:05 bdonlan Exp $

# haver-tk.pl, Perl/Tk client for Haver-compatible chat servers.
# Copyright (C) 2003 Bryan Donlan
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

use strict;
use warnings;
use Carp;
use Data::Dumper;

my $host = 'hardison.net';
my $port = 7070;
my $nick = $ENV{USER} || '';
my $pass = '';
my $curchannel = "lobby";

use Tk;
use POE qw(
  Wheel::SocketFactory
  Wheel::ReadWrite Driver::SysRW);
use Haver::Protocol::Filter;
use Haver::Client;

eval { require POE::Wheel::SSLSocketFactory; };
my $enable_ssl = !$@;

# XXX: SSLSocketFactory client connections don't work yet.
$enable_ssl = 0;

my $mw;
my $frame;
my $tbox;
my $entry;
my $aj;
my $ulist;
my @users;
my %users;

sub tbox_print {
    foreach (@_) {
        $tbox->insert( 'end', $_ . "\n" );
    }
    $tbox->yview('end');
}

sub update_ulist {
    my @users = sort keys %users;
    $ulist->delete( 0, 'end' );
    $ulist->insert( 0, @users );
}

sub _start {
    my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];

    Haver::Client->new('haver');
    $kernel->post('haver', 'register', 'all');

    $mw    = $poe_main_window;
    $mw->title('Haver');

    $frame = $mw->Frame();

    $tbox  = $frame->Scrolled( 'ROText', -scrollbars => 'one' );
    $aj    = $frame->Adjuster( -widget => $tbox, -side => 'left' );
    $ulist = $frame->Scrolled( 'Listbox', -scrollbars => 'one' );

    $tbox->pack( -side  => 'left', -fill => 'both', -expand => 1 );
    $ulist->pack( -side => 'left', -fill => 'both', -expand => 1 );

    $frame->pack( -fill => 'both', -expand => 1 );

    $entry = $mw->Entry();
    $entry->pack( -fill => 'x',    -expand => 0 );
    $entry->bind( '<Return>', $session->postback('input') );

    $kernel->delay('connect_win', 0.1);
}

my ($cwin, $hostbox, $portbox, $nickbox, $passbox, $use_ssl);

sub setup_connect_win {
    defined $cwin and return;
    my $session = shift;
    $cwin = $mw->Toplevel();
    $cwin->title('Connect to server');
    
    $cwin->Label(-text => 'Host:', -justify => 'right')
	->grid (-column => 0, -row => 0);
    $hostbox = $cwin->Entry()
	->grid (-column => 1, -row => 0);
    $hostbox->insert(0, $host);

    $cwin->Label(-text => 'Port:', -justify => 'right')
	->grid (-column => 0, -row => 1);
    $portbox = $cwin->Entry()
	->grid (-column => 1, -row => 1);
    $portbox->insert(0, $port);

# XXX: This breaks Tk for me.
#     $portbox->validateCommand
# 	(sub{
# 	    my $text = $_[0];
# 	    if($text =~ /\D/){
# 		return 0;
# 	    }
# 	    return 1;
# 	});
#     $portbox->validate('key');

    $cwin->Label(-text => 'UID:', -justify => 'right')
	->grid (-column => 0, -row => 2);
    $nickbox = $cwin->Entry()
	->grid (-column => 1, -row => 2);
    $nickbox->insert(0, $nick); 
    
    $cwin->Label(-text => 'Password:', -justify => 'right')
	->grid (-column => 0, -row => 3);
    $passbox = $cwin->Entry(-show => '*')
	->grid (-column => 1, -row => 3);
    $passbox->insert(0, $pass);

    $use_ssl = 0;
    if($enable_ssl){
	$cwin->Checkbutton(-text => 'Use SSL',
			   -variable => \$use_ssl)
	     ->grid(-column => 0, -row => 4, -columnspan => 2);
    }else{
	$cwin->Label(-text => 'SSL unavailable.',
		     -justify => 'center')
	     ->grid(-column => 0, -row => 4, -columnspan => 2);
    }
    
    $cwin->Button(-text => 'Connect',
		  -command => $session->postback('begin_connect'))
	->grid(-column => 0, -row => 5);
    
    $cwin->Button(-text => 'Quit',
		  -command => sub { exit })
	->grid(-column => 1, -row => 5);

    $cwin->focus;
}

sub begin_connect {
    my ($kernel, $heap) = @_[KERNEL,HEAP];
    $heap->{nick} = ($nick = $nickbox->get) or return;
    $pass = $passbox->get;
    $kernel->post('haver', 'connect', 
		  Host => ($host = $hostbox->get),
		  Port => ($port = $portbox->get),
		  );
    tbox_print "Connecting to $host:$port...";
    $cwin and $cwin->destroy;
    ($cwin, $hostbox, $portbox, $nickbox) = ();
}

sub haver_connected {
    my $heap = $_[HEAP];
    tbox_print("Connected.\n");
}

sub haver_login_request {
    my ($kernel, $heap) = @_[KERNEL,HEAP];
    tbox_print("Logging in as $nick...");
    $kernel->post(haver => login => $nick, (($pass ne '') ? $pass : undef));
}

sub haver_login {
    my ($kernel, $heap) = @_[KERNEL,HEAP];
    tbox_print("Logged in.");
    $pass = '';
    $kernel->post(haver => join => $curchannel);
    $heap->{ready} = 1;
}

my %commands = (
		users => sub {
		    my ($kernel, $heap, $args) = @_[KERNEL,HEAP,ARG0];
		    $kernel->post(haver => users => ($args ?
						     ($args) : ($curchannel)));
		    
		},
		quit => sub {
		    my ($kernel, $heap) = @_[KERNEL,HEAP];
		    tbox_print "Disconnecting...";
		    $heap->{closing} = 1;
		    $kernel->post(haver => 'disconnect');
		},
		msg => sub {
		    my ($kernel, $heap, $args) = @_[KERNEL,HEAP,ARG0];
		    unless($args =~ m!
			   ( 
			     # Quoted nicks, e.g:
			     # "bob the voting fish"
			     (?: [\"\'] [^\"\']+ [\"\'] ) |
			     \w+
			     )
			   \s+
			   (.+)
			   $ !x){
			tbox_print "Syntax error. msg";
			return;
		    }
		    my ($who, $msg) = ($1, $2);
		    $who =~ s/^[\'\"](.+)[\'\"]$/$1/;
		    $kernel->post(haver => pmsg => $who, $msg);
		    tbox_print "[To $who] $heap->{nick}: $msg";
		},
		me => sub {
		    my ($kernel, $heap, $args) = @_[KERNEL,HEAP,ARG0];
		    $kernel->post(haver => act => $curchannel, $args);
		},
		act => sub {
		    my ($kernel,$heap, $args) = @_[KERNEL,HEAP,ARG0];
		    unless($args =~ m!
			   ( 
			     # Quoted nicks, e.g:
			     # "bob the voting fish"
			     (?: [\"\'] [^\"\']+ [\"\'] ) |
			     \w+
			     )
			   \s+
			   (.+)
			   $ !x){
			tbox_print "Syntax error. msg";
			return;
		    }
		    my ($who, $msg) = ($1, $2);
		    $who =~ s/^[\'\"](.+)[\'\"]$/$1/;
		    $kernel->post(haver => pact => $who, $msg);
		    tbox_print "[To $who] $heap->{nick} $msg";
		}
		);

sub input {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    my $t = $entry->get;
    $entry->delete( 0, 'end' );
    $t =~ s/\t/' 'x8/ge;
    return if defined $heap->{closing};
    if ( !defined $heap->{ready} ) {
	tbox_print "Not connected.";
        return;
    }
    if ( $t =~ m!^/ (\w+) (?:\s+ (.+))? $!x) {
	if(exists $commands{lc $1}) {
	    $commands{lc $1}(@_[0..ARG0-1], $2);
	} else {
	    tbox_print "Unknown command: $1";
	}
	return;
    }
    if($t =~ m!^ / [^ ] !x) {
	tbox_print "Syntax error. nm";
	return;
    }
    $t =~ s!^/ !!;
    $kernel->post(haver => msg => $curchannel, $t);
}

sub haver_users { 
    my ($where, @who) = @_[ARG0..$#_];
    my $count = @who;
    tbox_print "[$count users in room $where]";
    tbox_print join(" - ", @who);
    %users = map { $_ => 1 } @who if $where eq $curchannel;
    update_ulist;
}

sub haver_public {
    my ($cid, $uid, $text) = @_[ARG0..ARG2];
    tbox_print "$uid: $text" if $cid eq $curchannel;
}

sub haver_pubact {
    my ($cid, $uid, $text) = @_[ARG0..ARG2];
    tbox_print "$uid $text" if $cid eq $curchannel;
}

sub haver_private {
    my ($uid, $text) = @_[ARG0..ARG2];
    tbox_print "=> $uid: $text";
}

sub haver_privact {
    my ($uid, $text) = @_[ARG0..ARG2];
    tbox_print "=> $uid $text";
}

sub haver_joined {
    my ($kernel, $channel) = @_[KERNEL,ARG0];
    tbox_print "[Joined $channel]";
    $kernel->post(haver => users => $channel);
}

sub haver_join {
    my ($kernel, $cid, $uid) = @_[KERNEL,ARG0,ARG1];
    tbox_print "[$uid has entered $cid]";
    $users{$uid} = 1 if $cid eq $curchannel;
    update_ulist
}

sub haver_part {
    my ($kernel, $cid, $uid) = @_[KERNEL,ARG0,ARG1];
    tbox_print "[$uid has left $cid]";
    delete $users{$uid} if $cid eq $curchannel;
    update_ulist
}

sub haver_quit {
    my ($kernel, $uid, $why) = @_[KERNEL,ARG0,ARG1];
    tbox_print "[$uid has quit: $why]";
    delete $users{$uid};
    update_ulist;
}

sub haver_disconnected {
    my ($kernel, $heap, $enum, $etxt) = @_[KERNEL,HEAP,ARG0,ARG1];
    if($enum == 0) {
	tbox_print "[Server closes connection. Disconnected.]";
    }elsif($enum == -1) {
	tbox_print "[Disconnected]";
    }else {
	tbox_print "[Connection error: $etxt ($enum)";
    }
    delete $heap->{ready};
    delete $heap->{closing};
    &setup_connect_win($_[SESSION]);
    return;
}

sub haver_close {
    my ($kernel, $heap, $etyp, $estr) = @_[KERNEL,HEAP,ARG0,ARG1];
    tbox_print "[Server closing connection: $estr]";
}

sub haver_connect_fail {
    my ($kernel, $heap, $etyp, $estr) = @_[KERNEL,HEAP,ARG0,ARG1];
    tbox_print "Unable to connect to server: $estr (#$etyp)";
    &setup_connect_win($_[SESSION]);
}

sub haver_login_fail {
    my ($kernel, $heap, $etyp, $estr) = @_[KERNEL,HEAP,ARG0,ARG1];
    tbox_print "Login failure: $estr";
# XXX: Redisplay login dialog
    $kernel->post(haver => 'disconnect');
    &setup_connect_win($_[SESSION]);
}

sub connect_win {
    &setup_connect_win($_[SESSION]);
}

sub _default {
    my ( $kernel, $state, $event, $args, $heap ) = @_[ KERNEL, STATE, ARG0, ARG1, HEAP ];
    $args ||= [];    # Prevents uninitialized-value warnings.
    print STDERR "default: $state = $event. Args:\n".Dumper $args;
    return 0;
}

POE::Session->create(
    package_states => [ main =>
        [qw(_start input begin_connect
	    connect_win haver_connected haver_login _default haver_users
	    haver_public
	    haver_pubact
	    haver_private
	    haver_privact
	    haver_joined
	    haver_join
	    haver_part
	    haver_quit
	    haver_disconnected
	    haver_close
	    haver_login_fail
	    haver_login_request
	    haver_connect_fail
	    )] ] );

POE::Kernel->run();
