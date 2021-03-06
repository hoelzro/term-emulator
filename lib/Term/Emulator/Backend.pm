## no critic (RequireUseStrict)
package Term::Emulator::Backend;

## use critic (RequireUseStrict)
use Moose::Role;

requires 'save';
requires 'handle_raw_input';
requires 'handle_tab';
requires 'handle_newline';
requires 'handle_set_attribute';
requires 'handle_set_fg_color';
requires 'handle_set_bg_color';
requires 'handle_cursor_move';
requires 'handle_cursor_set';

1;

__END__

# ABSTRACT: Backend objects for L<Term::Emulator>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=cut
