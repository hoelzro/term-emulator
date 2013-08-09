## no critic (RequireUseStrict)
package Term::Emulator::Backend::Cairo;

## use critic (RequireUseStrict)
use Moo;

with 'Term::Emulator::Backend';

sub save {
    my ( $self, $filename ) = @_;
}

1;

__END__

# ABSTRACT: Cairo backend for Term::Emulator

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head1 SEE ALSO

L<Term::Emulator::Backend>

=cut
