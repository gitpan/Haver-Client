# vim: set ts=4 sw=4 noexpandtab si ai sta tw=100:
# This module is copyrighted, see end of file for details.
package Haver::Client::Failures;
use strict;
use warnings;

use Haver::Base -base;

our $VERSION = 0.08;

field messages => {
    'invalid.name'      => "The server rejected the name %1.",
    'reserved.name'     => "The name %1 is reserved for internal use by the server.",
    'exists.user'       => "The name %1 is in use.",
    'unknown.user'      => "The user %1 is not online.",
    'unknown.channel'   => "The channel %1 does not exist.",
    'unknown.namespace' => "The namespace %1 does not exist. This is probably an application bug.",
    'invalid.type'      => "The type of a message was invalid. "
    	                . "This is almost certainly an application error.",
    'already.joined'    => "Tried to join %1 when already in it.",
    'already.parted'    => "Tried to leave %1 when not in it.",
};

sub add_message {
	my ($self, $code, $msg) = @_;
	$self->{messages}{$code} = $msg;
}
    
sub format {
	my ($self, @args) = @_;
    my $code = $args[0];

    unless (exists $self->{messages}{$code}) {
        return "Unknown error: " . join(' ', @args);
    }

    my $msg = $Failures{$code};
    $msg =~ s/%(\d+)/$args[$1] || "[MISSING ARGUMENT $1]"/eg;
    return $msg;
}



1;
__END__
=head1 NAME

Haver::Client::Failures - description

=head1 SYNOPSIS

	use Haver::Client::Failures;
	my $failures = new Haver::Client::Failures;
	my $desc = $failures->format('IDENT', 'invalid.name', '^fooo^');
	
	$desc eq "The server rejected the name ^fooo^."; # True
	
=head1 DESCRIPTION

FIXME

=head1 INHERITENCE

Haver::Client::Failures extends blaa blaa blaa

=head1 CONSTRUCTOR

List required parameters for new().

=head1 METHODS

This class implements the following methods:

=head2 method1(Z<>)

...

=head1 BUGS

None known. Bug reports are welcome. Please use our bug tracker at
L<http://gna.org/bugs/?func=additem&group=haver>.

=head1 AUTHOR

Dylan William Hardison, E<lt>dhardison@cpan.orgE<gt>

=head1 SEE ALSO

L<http://www.haverdev.org/>.

=head1 COPYRIGHT and LICENSE

Copyright (C) 2005 by Dylan William Hardison. All Rights Reserved.

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

