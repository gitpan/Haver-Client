# Haver::Protocol::Errors
# Exports hash of errors and contains usefulinformation in POD form.
# 
# Copyright (C) 2004 Dylan William Hardison
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
package Haver::Formats::Error;
use warnings;
use strict;

use base qw( Exporter );

our $VERSION = "0.02";
our @EXPORT = qw( );
our @EXPORT_OK = (@EXPORT, qw( %Errors ));

our %Errors = (
	WANT           => [
		'want unsatisfied',
		'Server wanted #1, but got #2',
		['expected', 'got'],
	],
	CANT_WRONG     => [
		'cant on unwanted thing',
		"Server didn't want anything, and got #1",
	],
	UID_IN_USE     => [
		'uid is in use',
		'Server says the uid #1 is already being used by someone else.',
	],
	CID_IN_USE     => [
		'cid is in use',
		'Server says the cid #1 already exists',
		['cid'],
	],
	CID_NOT_FOUND  => [
		'unknown channel id',
		'Server says the channel #1 does not exist.',
	],
	UID_NOT_FOUND  => [
		'unknown user id',
		'Server says the user #1 does not exist.',
	],
	UID_INVALID    => [
		'invalid uid',
		'Server says the uid #1 is not valid.',
	],
	UID_RESERVED   => [
		'uid is reserved',
		'Server says the uid #1 is reserved for future use.',
	],
	BUG            => [
		'this should never happen',
		'Server has encountered something that should never happen...',
	],
	UCMD            => [
		'unknown command',
		'Server does not recognize the command #1',
	],
	ALREADY_JOINED  => [
		'already joined to channel',
		'Server says you are already in the channel #1.',
		['channel'],
	],
	NOT_JOINED_PART => [
		'not joined to channel',
		'Server says you can not part #1 because you are not in there to begin with.',
	],
	FIELD_NOT_FOUND => [
		'field not defined',
		'Server says the field #1 does not exist on that object',
		['field'],
	],
	ARG_INVALID => [
		'argument not valid',
		'Server says argument number #2 to command #1 is invalid.',
		['command name', 'argument number'],
	],
	UNEXPECTED_PONG => [
		'pong not expected',
		'Server did not expect client to send PONG.',
		[],
	],
	SPEEDY => [
		'you are too fast',
		'Server does not like you to speak unless asked until you are accepted...',
		[],
	],
	PASS_INVALID => [
		'password is invalid',
		'Server says the password you sent was invalid.',
		[],
	],
	ACCESS => [
		'access denied',
		'Server says you are not allowed to access the #1 command',
		['command'],
	],
);

sub new {
	my ($this) = @_;
	return $this;
}

sub get_long_desc {
	my ($this, $err, @args) = @_;
	return $Errors{$err}[1];
}

sub format {
	my ($this, $s, @args) = @_;
	$s =~ s/\#(\d+?)/$args[$1-1]/ge;
	return $s;
}

sub get_short_desc {
	my ($this, $err) = @_;
	return $Errors{$err}[0];
}

sub dump_errors {
	my ($this) = @_;
	foreach my $k (keys %Errors) {
		my $short = $Errors{$k}[0];
		my $msg = $Errors{$k}[1];
		my $args = join(',', @{ $Errors{$k}[2] || [] });
		print "$k\t$short\t$msg\t$args\n";
	}
}

1;
__END__

=head1 NAME

Haver::Protocol::Errors - Error routines and data.

=head1 SYNOPSIS

   use Haver::Protocol::Errors qw(%Errors);
   my ($short_desc, $long_desc) = @{ $Errors{ UID_NOT_FOUND } };

   # or
   $short_desc = Haver::Protocol::Errors->get_short_desc('UCMD');
   $long_desc  = Haver::Protocol::Errors->get_long_desc('UCMD');

   # Formatting:
   $s = Haver::Protocol::Errors->format($Errors{$err}[1], $arg1);
 
=head1 DESCRIPTION

This is a class for turning Haver error codes into
human-readable strings.

=head1 METHODS

=over 1

=item my $e = new Haver::Protocol::Errors

This doesn't actually make a new object. it just
returns "Haver::Protocol::Errors". This is because
this module only provides class methods. But I'm lazy and want
to write $e here instead of Haver::Protocol::Errors.

=item $s = $e->short_desc($err)

$s is short string describing the error $err. 

=item $s = $e->long_desc($err)

$s is a longer string. It will contain "#n", where n is a nonzero number.
You will want to pass $s to $s->format().

=item $s = $e->format( $e->long_desc($err) )

This $s can be presented to the user. It should
be fairly easy to understand and such.

=item $s = $e->dump_errors()

$s is a string comtaining all errors. The format is:

Error code (tab) short_desc (tab) long_desc (tab) [comma-seperated list of descriptions of #-interpolations] NEWLINE [...]

=back

=head1 SEE ALSO

L<Haver::Protocol>.

L<https://savannah.nongnu.org/projects/haver/>, L<http://wiki.chani3.com/wiki/ProjectHaver/Protocol>,
L<http://wiki.chani3.com/wiki/ProjectHaver/ProtocolSyntax>.

=head1 AUTHOR

Dylan William Hardison, E<lt>dylanwh@tampabay.rr.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Dylan William Hardison

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
