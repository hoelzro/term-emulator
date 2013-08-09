## no critic (RequireUseStrict)
package Term::Emulator;

## use critic (RequireUseStrict)
use Moo;
use IO::Pty;

has [qw/width height/] => (
    is => 'ro',
);

has backend => (
    is      => 'ro',
    handles => [qw/save/],
);

sub execute {
    my ( $self, @args ) = @_;

    $self->execute_background(@args);
    $self->wait;

    return;
}

sub execute_background {
    my ( $self, @args ) = @_;
}

sub execute_bg {
    my ( $self, @args ) = @_;

    return $self->execute_background(@args);
}

sub wait {
    my ( $self ) = @_;
}

sub attach {
    my ( $self ) = @_;
}

sub feed {
    my ( $self, $input ) = @_;
}

sub reset {
    my ( $self ) = @_;
}

1;

__END__

# ABSTRACT: Interprets terminal escape sequences

=head1 SYNOPSIS

    use Term::Emulator;

    # Basic Usage
    my $term = Term::Emulator->new;

    # run a child program
    $term->execute('ls');

    # save its output
    $term->save('ls-output.png');

    # Advanced Usage

    # $term->execute(@args) is really shorthand for...
    my $pid = fork();

    if($pid) {
        waitpid $pid, 0;
    } else {
        $term->attach; # ASSUMING DIRECT CONTROL
        exec @args;
    }

    # Explicit Dimensions
    my $term = Term::Emulator->new(
        width  => 80,
        height => 25,
    );

    # Background Processes
    $term->execute_background('vim');
    $term->feed(":q\n");
    $term->wait;

    # Explicit Backend
    my $term = Term::Emulator->new(
        backend => Term::Emulator::Backend::Logger->new,
    );

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 width

The width of the terminal to create, in columns.  Defaults to the
width of the current terminal.

=head2 height

The height of the terminal to create, in rows.  Defaults to the
height of the current terminal.

=head2 backend

The backend to handle actions specified by the terminal sequences.
Must consume the L<Term::Emulator::Backend> role.  Defaults to
L<Term::Emulator::Backend::Cairo>.

=head1 METHODS

=head2 Term::Emulator->new(%options)

Creates a new L<Term::Emulator> object.  The valid key/value pairs for
C<%options> are any of the attributes listed under L</ATTRIBUTES>.

=head2 $term->execute(@args)

Executes a new program using this L<Term::Emulator> object as the terminal
and waits for it to exit (ie. functions like L<system>).  L<@args> are fed
directly to L<exec>, so no shell shenanigans work here.

Dies if a background process is currently running.

=head2 $term->execute_background(@args)

Executes a new program using this L<Term::Emulator> object as the terminal
and lets it run in the background.  You can feed new input to it via
L</feed>, or wait for it via L</wait>.  Returns the pid of the new process.

Dies if a background process is currently running.

=head2 $term->execute_bg(@args)

An alias for L</execute_background>.

=head2 $term->save($filename)

Saves the current terminal output to C<$filename>.  This really just forwards
to the C<save> method of the backend object, so check your backend's
documentation.

=head2 $term->attach()

Sets up this L<Term::Emulator> object as the terminal for the current process.
You should rarely have to do this, and when you do, it'll likely be from a
child process.

=head2 $term->feed($input)

Feeds the given input to the terminal.  Dies if no background process is
running.

=head2 $term->wait()

Waits for the current background process to exit.  Dies if there is no
background process to wait for.

=head2 $term->reset()

Resets the terminal's state.  This may come in handy when running several
programs and you don't want them to step on each others' toes.

=cut
