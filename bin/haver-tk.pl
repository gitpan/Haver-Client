#!/usr/bin/perl
# $Header: /cvsroot/haver/haver/client/bin/haver-tk.pl,v 1.1 2004/02/16 03:52:52 dylanwh Exp $

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

use constant {
    CLIENT_NAME => 'haver-tk'
};

BEGIN {
    my $v = '$Revision: 1.1 $';
    $v =~ s/^[^0-9.]+//;
    $v =~ s/[^0-9.]+$//;
    $v = "haver-tk.pl/CVS:$v";
    *CLIENT_VERSION = sub { $v };
}

my $host = 'hardison.net';
my $port = 7070;
my $nick = $ENV{USER} || '';
my $curchannel = "lobby";

use Tk;
use POE qw(
  Wheel::SocketFactory
  Wheel::ReadWrite Driver::SysRW);
use Haver::Protocol::Filter;

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

my ($cwin, $hostbox, $portbox, $nickbox, $use_ssl);

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
    
    $use_ssl = 0;
    if($enable_ssl){
	$cwin->Checkbutton(-text => 'Use SSL',
			   -variable => \$use_ssl)
	     ->grid(-column => 0, -row => 3, -columnspan => 2);
    }else{
	$cwin->Label(-text => 'SSL unavailable.',
		     -justify => 'center')
	     ->grid(-column => 0, -row => 3, -columnspan => 2);
    }
    
    $cwin->Button(-text => 'Connect',
		  -command => $session->postback('begin_connect'))
	 ->grid(-column => 0, -row => 4);

    $cwin->Button(-text => 'Quit',
		  -command => sub { exit })
	 ->grid(-column => 1, -row => 4);

    $cwin->focus;
}

sub begin_connect {
    my $heap = $_[HEAP];
    $heap->{nick} = ($nick = $nickbox->get) or return;
    if ( $heap->{sock} ) {
        tbox_print "Connection already in progress!\n";
        return;
    }
    if(!$use_ssl){
	$heap->{sock} = new POE::Wheel::SocketFactory
	    (
	     RemoteAddress => ($host = $hostbox->get),
	     RemotePort    => ($port = $portbox->get),
	     SuccessEvent  => 'on_connect',
	     FailureEvent  => 'on_fail'
	     );
    }else{
	$heap->{sock} = new POE::Wheel::SSLSocketFactory
	    (
	     RemoteAddress => ($host = $hostbox->get),
	     RemotePort    => ($port = $portbox->get),
	     SuccessEvent  => 'on_connect',
	     FailureEvent  => 'on_fail'
	     );
    }
    tbox_print "Connecting to $host:$port...";
    $cwin and $cwin->destroy;
    ($cwin, $hostbox, $portbox, $nickbox) = ();
}

sub on_connect {
    my ( $heap, $hand, $ssl ) = @_[ HEAP, ARG0, ARG4 ];
    if(!$use_ssl){
	$heap->{drv}  = POE::Driver::SysRW->new();
    }else{
	$heap->{drv}  = POE::Driver::SSL->new( SSL => $ssl );
    }
    $heap->{filt} = Haver::Protocol::Filter->new();
    $heap->{net}  = POE::Wheel::ReadWrite->new(
        Handle     => $hand,
        Driver     => $heap->{drv},
        Filter     => $heap->{filt},
        InputEvent => 'net_in',
        ErrorEvent => 'net_err'
    );
    tbox_print("Connected. Logging in as $heap->{nick}\n");
}

sub on_fail {
    my ( $session, $operation, $errnum, $errstr, $wheel_id ) =
	@_[ SESSION, ARG0 .. ARG3 ];
    my $heap = $_[HEAP];
    tbox_print "Unable to connect: $errstr";
    delete $heap->{sock};
    &setup_connect_win($session);
}

my %events = (
	      MSG => sub {
		  my @args = @_[ARG0..$#_];
		  tbox_print "$args[1]: $args[2]";
	      },
	      PMSG => sub {
		  my ($who, $what) = @_[ARG0, ARG1];
		  tbox_print "[From $who] $what";
	      },
	      ACCEPT => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  tbox_print "[Server accepted uid $args[0]]";
		  $heap->{net}->put( ['JOIN', 'lobby'] );
	      },
	      REJECT => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  tbox_print "[Server rejected uid $args[0]: $args[1]]";
		  %{$heap} = ();
		  %users = ();
		  update_ulist;
		  &setup_connect_win($_[SESSION]);
	      },
	      JOIN => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  tbox_print "[$args[1] has entered $args[0]]";
		  if ($args[1] eq $heap->{nick}) {
			  $heap->{net}->put( ['USERS', 'lobby'] );
		  } else {
			  $users{$args[1]} = 1;
		  update_ulist;
		  }
	      },
	      PART => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  delete $users{$args[1]};
		  tbox_print "[$args[1] has left $args[0]]";
		  update_ulist;
	      },
	      ERROR => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  tbox_print "[Error: $args[0]  $args[1]]";
	      },
	      USERS => sub {
		  my ($heap, $channel, @args) = @_[HEAP, ARG0..$#_];
		  tbox_print "[Users for $channel]", map { " - $_" } @args;
		  if ($curchannel eq $channel) {
		      %users = ();
		      $users{$_} = 1 for (@args);
		  }
		  update_ulist;
	      },
	      PING => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  $heap->{net}->put( ['PONG', @args] );
	      },
	      WANT => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  if ($args[0] eq 'VERSION') {
		      $heap->{net}->put( ['VERSION', CLIENT_VERSION] );
		  }
		  elsif ($args[0] eq 'LOGIN' || $args[0] eq 'UID') {
		      $heap->{net}->put( [$args[0], $heap->{nick} ] );
		  }
		  else {
		      tbox_print "Unknown WANT: $args[0]";
		      $heap->{net}->put( ['CANT', $args[0]] );
		  }
	      },
	      CLOSE => sub {
		  my ($heap, @args) = @_[HEAP, ARG0..$#_];
		  tbox_print "Server closing connection: $args[0]";
		  $heap->{silence_dc_error} = 1;
	      }
	      );
sub net_in {
    my ( $heap, $arg ) = @_[ HEAP, ARG0 ];
    my ( $cmd, @args ) = @{$arg};
    $heap->{silence_dc_error} = 0;
    if(exists $events{$cmd}){
	$events{$cmd}->(@_[0..ARG0 - 1], @args);
    } else {
	tbox_print "Unknown server message:";
	tbox_print Dumper $arg;
    }
}

sub net_err {
    my ( $heap, $session, $operation, $errnum, $errstr, $wheel_id ) =
      @_[ HEAP, SESSION, ARG0 .. ARG3 ];
    unless($heap->{silence_dc_error}){
	tbox_print "Connection error: $errstr";
    }
    tbox_print "Disconnected.";
    %users = ();
    %{$heap} = ();
    update_ulist;
    &setup_connect_win($session);
}

my %commands = (
		users => sub {
		    my ($heap, $args) = @_[HEAP,ARG0];
		    $heap->{net}->put( ["USERS", ($args ?
						  ($args) : ($curchannel))] );
		},
		quit => sub {
		    my $heap = $_[HEAP];
		    tbox_print "Disconnecting.";
		    %{$heap} = ();
		    %users = ();
		    update_ulist;
		    &setup_connect_win($_[SESSION]);
		},
		msg => sub {
		    my ($heap, $args) = @_[HEAP,ARG0];
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
		    $heap->{net}->put( [ "PMSG", $who, $msg ] );
		    tbox_print "[To $who] $msg";
		}
		);

sub input {
    my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
    my $t = $entry->get;
    $entry->delete( 0, 'end' );
    $t =~ s/\t/' 'x8/ge;
    if ( !defined $heap->{sock} ) {
#        begin_connect $heap, $host, $port, $t;
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
    $heap->{net}->put( [ "MSG", 'lobby', $t ] );
}

sub connect_win {
    &setup_connect_win($_[SESSION]);
}

POE::Session->create(
    package_states => [ main =>
        [qw(net_in net_err on_fail on_connect _start input begin_connect
	    connect_win
	    )] ] );

POE::Kernel->run();
