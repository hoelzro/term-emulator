## no critic (RequireUseStrict)
package Term::Emulator::Backend;

## use critic (RequireUseStrict)
use Moose::Role;

requires 'save';
requires 'handle_raw_input';
requires 'handle_tab';

1;

__END__

# ABSTRACT: Backend objects for L<Term::Emulator>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=cut
