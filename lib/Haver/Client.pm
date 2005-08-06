# vim: set ft=perl ts=4 sw=4:
# Haver::Client - A POE::Component for haver clients.
# 
# Copyright (C) 2004, 2005 Bryan Donlan, Dylan Hardison.
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

# XXX Is this accurate? Does it even belong here? XXX
# heap fields:
# heap => {
#   version => client version
#   name => user name,
#   reg  => {
#     event name => { session ID => 1 }
#   },
#   wheel => active wheel,
#   state => see below constants,
#   # for connect events sent while still shutting down
#   pending => { Host => host, Port => port, Name => name ] | nonexistent
# }
package Haver::Client;
use strict;
use warnings;

use Haver::Session -base;
use POE;
use POE::Wheel::ReadWrite;
use POE::Wheel::SocketFactory;
use Haver::Protocol::Filter;

use constant {
    S_IDLE   => 0, # not connected, not connecting
    S_CONN   => 1, # establishing socket connection
    S_INIT   => 2, # C: HAVER sent
    S_LOGIN  => 3, # S: HAVER recieved, C: IDENT sent
    S_ONLINE => 4, # S: HELLO received
    S_DYING  => 5, # C: BYE sent, socket still open
};

our $VERSION = 0.08;

sub dispatch {
    call('dispatch', @_);
}

### SETUP

sub states {
	local *prefix = sub {
		my $prefix = shift;
		map { ($_ => $prefix . $_) } @_;
	};
	
	
	return {
		prefix('on_', qw(
				_start _default _stop
				connect  connect_fail 
				connect_ok disconnect
				input  send_raw send 
				join part public private
				list destroy
				dispatch
				register unregister
				cleanup error
				force_down dns_response
				do_connect
			)),
		map { ("msg_$_", "msg_$_") } qw(
			HAVER HELLO
			JOIN PART
			IN FROM
			PING BYE
			FAIL
		)
	};
}

sub on__start {
    my ($kernel, $heap, $opt) = @_[KERNEL, HEAP, ARG0];
    croak "No alias" unless $opt->{alias};
    $heap->{reg}      = {};
    $heap->{state}    = S_IDLE;
    $heap->{alias}    = $opt->{alias};
    $heap->{resolver} = $opt->{resolver};
    $heap->{version}  = $opt->{version} || "Haver::Client/$VERSION";
    
    $kernel->alias_set($opt->{alias});
}

sub on__default {
	my ( $kernel, $state, $event, $args, $self ) = @_[ KERNEL, STATE, ARG0, ARG1, OBJECT ];
	$args ||= [];	# Prevents uninitialized-value warnings.
	return 0;
}

sub on__stop {   }

### SESSION MANAGEMENT

sub on_connect {
    my ($kernel, $heap, %opts) = @_[KERNEL,HEAP,ARG0..$#_];
    $opts{port} ||= 7575;
    
    # TODO: handle arg errors
    if ($heap->{state} == S_DYING) {
        $heap->{pending} = \%opts;
        return;
    } elsif ($heap->{state} != S_IDLE) {
        call('disconnect');
        $heap->{pending} = \%opts;
    } else {
        $heap->{state} = S_CONN;
        $heap->{name}  = $opts{name};
        $heap->{port}  = $opts{port};
        if (!$heap->{resolver}) {
            call('do_connect', $opts{host});
        } else {
            my $resp = $heap->{resolver}->resolve(
                host  => $opts{host},
                context => {},
                event => 'dns_response',
            );
            if ($resp) {
                call('dns_response', $resp);
            }
        }
    }
}

sub on_do_connect {
    my ($heap, $addr) = @_[HEAP,ARG0];
    my $port = delete $heap->{port};
    if ($heap->{state} == S_DYING) {
        call('cleanup');
        return;
    }
    $heap->{wheel} = POE::Wheel::SocketFactory->new(
        RemoteAddress => $addr,
        RemotePort    => $port,
        SuccessEvent  => 'connect_ok',
        FailureEvent  => 'connect_fail',
    );
}

BEGIN {
    eval {
        require List::Util;
        List::Util->import(qw(shuffle));
    };
    eval {
        shuffle();
    };
    if ($@) {
        *shuffle = sub { return @_; }
    }
}

sub on_dns_response {
    my ($heap, $packet) = @_[HEAP,ARG0];
    if ($packet->{response}) {
        my $resp = $packet->{response};
        my @answer = shuffle($resp->answer);
        foreach my $record (@answer) {
            if ($record->type eq 'A') {
                # XXX: ipv6 support
                $poe_kernel->yield('do_connect', $record->address);
                return;
            }
        }
        # dns fail
        dispatch('connect_fail', 'dns');
        call('cleanup');
    } else {
        dispatch('connect_fail', 'dns', $packet->{error});
    }
}

sub on_connect_fail {
    my $heap = $_[HEAP];
    dispatch('connect_fail', @_[ARG0..ARG2]);
    call('cleanup');
}

sub on_connect_ok {
    my ($kernel, $heap, $sock) = @_[KERNEL,HEAP,ARG0];
    if ($heap->{state} == S_DYING) {
        call('cleanup');
        return;
    }
    dispatch('connected');
    $heap->{state} = S_INIT;
    $heap->{wheel} = new POE::Wheel::ReadWrite(
        Handle => $sock,
        Filter => new Haver::Protocol::Filter,
        InputEvent => 'input',
        ErrorEvent => 'error',
    );
    $heap->{wheel}->put( ['HAVER', $heap->{version}] );
    # XXX: timeout
}

sub on_input {
    my ($kernel, $heap, $arg) = @_[KERNEL,HEAP,ARG0];
    return if (ref $arg ne 'ARRAY' || @$arg == 0);
    print STDERR "S: ", join "\t", @$arg;
    print STDERR "\n";
    dispatch('raw_in', @$arg);
    my $cmd = $arg->[0];
    $cmd =~ tr/:/_/;
    $kernel->yield("msg_$cmd", @$arg);
}

sub on_error {
    dispatch('disconnected', @_[ARG0..ARG2]);
    call('cleanup');
}


sub on_disconnect {
    my $heap = $_[HEAP];
    call('send_raw', 'BYE');
    $heap->{state} = S_DYING;
    $poe_kernel->delay('force_down', 5);
}

sub on_force_down {
    my $heap = $_[HEAP];
    $heap->{state} = S_IDLE;
    call('cleanup');
}

sub on_cleanup {
    my $heap = $_[HEAP];
    $poe_kernel->delay('force_down');
    if ($heap->{pending}) {
        my @opts = %{delete $heap->{pending}};
        $poe_kernel->yield('connect', @opts);
    }
    delete $heap->{wheel};
    delete $heap->{name};
    $heap->{state} = S_IDLE;
}

sub on_send_raw {
    my ($heap, @args) = @_[HEAP,ARG0..$#_];
    if ($heap->{state} == S_IDLE || $heap->{state} == S_CONN ||
        $heap->{state} == S_DYING) {
        return;
    }
    print STDERR "C: ", join("\t", @args), "\n";
    $heap->{wheel}->put(\@args);
}

sub on_send {
    my ($kernel, @args) = @_[KERNEL,ARG0..$#_];
    call('send_raw', @args);
}

sub on_join {
    my $channel = $_[ARG0];
    call('send', 'JOIN', $channel);
}

sub on_part {
    my $channel = $_[ARG0];
    call('send', 'PART', $channel);
}

sub on_public {
    my ($kernel, $heap, $c, $t, @a) = @_[KERNEL,HEAP,ARG0..$#_];
    call('send', 'IN', $c, $t, @a);
}

sub on_private {
    my ($kernel, $heap, $d, $t, @a) = @_[KERNEL,HEAP,ARG0..$#_];
    call('send', 'TO', $d, $t, @a);
}

sub on_list {
    my ($chan, $type) = @_[ARG0, ARG1];
    $type = defined $type ? $type : 'user';
    call('send', 'LIST', $chan, $type);
}

sub on_destroy {
	my ($kernel, $heap) = @_[KERNEL,HEAP];
    dispatch('destroyed');
    delete $heap->{pending};
    my $reg = $heap->{reg};
    foreach my $ehash (values %$reg) {
        foreach my $id (keys %$ehash) {
            $poe_kernel->refcount_decrement($id, $ehash->{$id});
        }
    }
    $heap->{reg} = {};
    call('disconnect');
    $kernel->alias_remove($heap->{alias});
}

## server-response stuff

sub msg_HAVER {
    my ($kernel, $heap) = @_[KERNEL,HEAP];
    return if ($heap->{state} != S_INIT); # should never happen, unless the
                                          # server is non-compliant
    $kernel->yield('send_raw', 'IDENT', $heap->{name});
    $heap->{state} = S_LOGIN;
}

sub msg_HELLO {
    my $heap = $_[HEAP];
    $heap->{state} = S_ONLINE;
    dispatch('ready');
}

sub msg_JOIN {
    my ($heap, $chan, $name) = @_[HEAP,ARG1,ARG2];
    if ($name eq $heap->{name}) {
        dispatch('ijoined', $chan);
    } else {
        dispatch('join', $chan, $name);
    }
}

sub msg_PART {
    my ($heap, $chan, $name) = @_[HEAP,ARG1,ARG2];
    if ($name eq $heap->{name}) {
        dispatch('iparted', $chan);
    } else {
        dispatch('part', $chan, $name);
    }
}

sub msg_LIST {
    my ($heap, $chan, $ns, @things) = @_[HEAP,ARG1..$#_];
    return unless defined $ns;
    dispatch('list', $chan, $ns, @things);
}

sub msg_IN {
    dispatch('public', @_[ARG1..$#_]);
}

sub msg_FROM {
    dispatch('private', @_[ARG1..$#_]);
}

sub msg_PING {
    call('send_raw', 'PONG', @_[ARG1..$#_]);
}

sub msg_BYE {
    my ($type, $detail) = @_[ARG2,ARG3];
    dispatch('bye', $detail);
    call('cleanup');
}

sub msg_FAIL {
	my ($kernel, $heap, $cmd, $code, @args) = @_[KERNEL, HEAP, ARG0 .. $#_];
	
    dispatch('fail', $cmd, $code, \@args);
    $code =~ tr/./_/;
    dispatch("fail_$code", $cmd, \@args);
}

sub on_register {
	my ($kernel, $heap, $sender, @events) = @_[KERNEL,HEAP,SENDER,ARG0..$#_];
    my $reg = $heap->{reg};
    my $id  = $sender->ID;
    
    foreach my $event (@events) {
        $event = uc $event;
        next if exists $reg->{$event}{$id};
        # Tags don't need to be anything special...
        #my $tag = '1' . $reg->{$event} . '\0' . $id . '\0' . rand;
        my $tag = __PACKAGE__;
        $reg->{$event}{$id} = $tag;
        $kernel->refcount_increment( $id, $tag );
    }
}

sub on_unregister {
	my ($kernel, $heap, $sender, @events) = @_[KERNEL, HEAP, SENDER, ARG0..$#_];
    my $reg = $heap->{reg};
    my $id  = $sender->ID;
    
    foreach my $event (@events) {
        $event = uc $event;
        my $tag;
        next unless $tag = delete $reg->{$event}{$id};
        $kernel->refcount_decrement( $id, $tag );
    }
}


sub on_dispatch {
    my ($kernel, $heap, $evname, @args) = @_[KERNEL,HEAP,ARG0..$#_];
    $evname = uc $evname;
    my $reg = $heap->{reg};
    $reg->{$evname} ||= {};
    $reg->{ALL}     ||= {};
    my %targ = (%{$reg->{$evname}}, %{$reg->{ALL}});
    my @ids  = keys %targ;

    unshift @args, [$heap->{alias}];

    foreach my $id (@ids) {
        $kernel->post($id, "haver_$evname", @args);
    }
}

1;

__END__

=head1 NAME

Haver::Client - POE component for haver clients.

=head1 SYNOPSIS

  use Haver::Client;
  create Haver::Client (
      alias => 'haver',
      resolver => $res, # A POE::Component::Client::DNS object
      version  => "WackyClient/1.20",
  );

  $kernel->post('haver', 'connect',
      host => 'hardison.net',
      name => ucfirst($ENV{USER}),
      port => 7575,
  );

     
=head1 DESCRIPTION

This module eases the creation of Haver clients. It provides a POE::Component in the style of 
L<POE::Component::IRC>, with some improvements.

=head1 METHODS

There is only one method, create(), which is a class method.

=head2 create(alias => $alias, resolver => $resolver, version => $version)

This creates a new Haver::Client session. The only required parameter
is $alias, which is how you'll talk to the client session using L<POE::Kernel>'s post().

If given, $resolver should be a L<POE::Component::Client::DNS> object.

Finally, $version is what we will advertize as the client name and version number to the
server. It defaults to C<Haver::Client/0.08>.

=head1 STATES

While these are listed just like methods, you must post() to them, and not call them
directly.

=head2 connect(host => $host, name => $name, [ port => 7575 ])

Connect to $host on port $port (defaults to 7575) with the user name $name.
If already connected to a server, Haver::Client will disconnect and re-connect using the
new settings.

=head2 register(@events)

This summons the sun god Ra and makes him eat your liver.

FIXME: This is inaccurate.

=head1 BUGS

None known. Bug reports are welcome. Please use our bug tracker at
L<http://gna.org/bugs/?func=additem&group=haver>.

=head1 AUTHOR

Bryan Donlan E<lt>bdonlan@haverdev.orgE<gt>,
Dylan Hardison E<lt>dylan@haverdev.orgE<gt>.

=head1 SEE ALSO

L<http://www.haverdev.org/>.

=head1 COPYRIGHT and LICENSE

Copyright (C) 2004, 2005 by Bryan Donlan, Dylan Hardison. All Rights Reserved.

This module is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This module is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this module; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

