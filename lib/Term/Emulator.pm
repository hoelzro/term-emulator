## no critic (RequireUseStrict)
package Term::Emulator;

## use critic (RequireUseStrict)
use Carp qw(croak);
use Moo;
use IO::Pty;
use Term::ReadKey qw(GetTerminalSize SetTerminalSize);

has [qw/width height/] => (
    is => 'lazy',
);

has backend => (
    is      => 'lazy',
    handles => [qw/save/],
);

has _pty => (
    is => 'rw',
);

has _background_pid => (
    is => 'rw',
);

sub BUILD {
    my ( $self ) = @_;

    $self->_pty(IO::Pty->new);

    return;
}

sub _build_width {
    # XXX hardcoded STDIN!
    my ( $width, undef ) = GetTerminalSize(\*STDIN);
    return $width;
}

sub _build_height {
    # XXX hardcoded STDIN!
    my ( undef, $height ) = GetTerminalSize(\*STDIN);
    return $height;
}

sub _build_backend {
    require Term::Emulator::Backend::Cairo;

    return Term::Emulator::Backend::Cairo->new;
}

sub execute {
    my ( $self, @args ) = @_;

    $self->execute_background(@args);
    $self->wait;

    return;
}

sub execute_background {
    my ( $self, $command, @args ) = @_;

    croak "Background process $self->_background_pid already running" if defined $self->_background_pid;

    my $pid = fork;

    croak "Unable to create child process: $!" unless defined $pid;

    if($pid) {
        $self->_background_pid($pid);
        $self->_pty->slave; # make sure we have a slave
        $self->_pty->close_slave;
        return $pid;
    } else {
        $self->attach;
        exec $command ( $command, @args );
    }
}

sub execute_bg {
    my ( $self, @args ) = @_;

    return $self->execute_background(@args);
}

sub wait {
    my ( $self ) = @_;

    croak "No background process running" unless defined $self->_background_pid;

    my $pty    = $self->_pty;
    my $buffer = ' ';

    # XXX where else should we do this reading?
    while(sysread($pty, $buffer, 1)) {
        use feature qw(say);
        say ord($buffer);
    }

    waitpid $self->_background_pid, 0;
    return;
}

sub attach {
    my ( $self ) = @_;

    my $pty   = $self->_pty;
    my $slave = $pty->slave;

    $pty->make_slave_controlling_terminal;
    $slave->set_raw;

    close $pty;

    open STDIN,  '<&', $slave;
    open STDOUT, '>&', $slave;
    open STDERR, '>&', $slave;

    # XXX 0 for pixel values (for now)
    SetTerminalSize($self->width, $self->height, 0, 0);

    return;
}

sub feed {
    my ( $self, $input ) = @_;

    croak "No background process running" unless defined $self->_background_pid;

    print { $self->_pty } $input;
    return;
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
