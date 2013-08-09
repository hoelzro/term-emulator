## no critic (RequireUseStrict)
package Term::Emulator::Backend::Cairo;

## use critic (RequireUseStrict)
use Moo;
use Cairo;

with 'Term::Emulator::Backend';

# XXX hardcoded
my $CHAR_WIDTH  = 10;
my $CHAR_HEIGHT = 20;

has [qw/width height/] => (
    is       => 'ro',
    required => 1,
);

has [qw/_surface _context/] => (
    is => 'rw',
);

sub BUILD {
    my ( $self ) = @_;

    # XXX allow more flexible surfaces
    my $surface = Cairo::ImageSurface->create('rgb24',
        $CHAR_WIDTH  * $self->width,
        $CHAR_HEIGHT * $self->height,
    );
    my $cr = Cairo::Context->create($surface);

    $cr->set_source_rgb(1, 1, 1);
    $cr->select_font_face('sans', 'normal', 'normal');
    $cr->set_font_size(20);
    $cr->move_to(0, 20);

    $self->_surface($surface);
    $self->_context($cr);
}

sub save {
    my ( $self, $filename ) = @_;

    # XXX allow other file types
    $self->_surface->write_to_png($filename);
}

sub handle_tab {
    my ( $self ) = @_;

    $self->_context->show_text(' ' x 8);
}

sub handle_raw_input {
    my ( $self, $input ) = @_;

    $self->_context->show_text($input);
    # XXX update cursor

    # XXX handle length($input) > 1
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
