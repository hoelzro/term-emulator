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

my $FIRST_FG_COLOR = 30;
my $FIRST_BG_COLOR = 40;
my $LAST_BG_COLOR  = 49;

my %ATTRIBUTE_FOR_CODE = (
    0  => 'normal',
    1  => 'bold',
    4  => 'underlined',
    5  => 'blink',
    7  => 'inverse',
    8  => 'hidden',
    22 => 'normal',
    24 => '-underlined',
    25 => '-blink',
    27 => '-inverse',
    28 => '-hidden',
);

# XXX should we delegate these definitions to the backend?
my %FG_COLOR_FOR_CODE = (
    30 => [ 0,    0,    0 ],
    31 => [ 0xFF, 0,    0 ],
    32 => [ 0,    0xFF, 0 ],
    33 => [ 0xFF, 0xFF, 0 ],
    34 => [ 0,    0,    0xFF ],
    35 => [ 0xFF, 0,    0xFF ],
    36 => [ 0,    0xFF, 0xFF ],
    37 => [ 0xFF, 0xFF, 0xFF ],
    #39 => original,
);

my %BG_COLOR_FOR_CODE = (
    40 => [ 0,    0,    0 ],
    41 => [ 0xFF, 0,    0 ],
    42 => [ 0,    0xFF, 0 ],
    43 => [ 0xFF, 0xFF, 0 ],
    44 => [ 0,    0,    0xFF ],
    45 => [ 0xFF, 0,    0xFF ],
    46 => [ 0,    0xFF, 0xFF ],
    47 => [ 0xFF, 0xFF, 0xFF ],
    #49 => original,
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
    my ( $self ) = @_;

    require Term::Emulator::Backend::Cairo;

    return Term::Emulator::Backend::Cairo->new(
        width  => $self->width,
        height => $self->height,
    );
}

sub execute {
    my ( $self, @args ) = @_;

    $self->execute_background(@args);
    $self->wait;

    return;
}

# XXX make sure you set TERM
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
        die "Cannot execute $command: $!";
    }
}

sub execute_bg {
    my ( $self, @args ) = @_;

    return $self->execute_background(@args);
}

sub _handle_escape_sequence {
    my ( $backend, $pty ) = @_;

    my $buffer = ' ';

    # XXX grab more than one byte at a time?
    # XXX handle error
    sysread($pty, $buffer, 1);

    my @params;

    use feature qw(say);
    if($buffer eq '[') {
        # XXX handle error
        while(sysread($pty, $buffer, 1)) {
            if($buffer =~ /[0-9]/) {
                push @params, '' if @params == 0;
                $params[$#params] .= $buffer;
                next;
            } elsif($buffer eq ';') {
                push @params, '';
                next;
            } elsif($buffer eq 'm') {
                foreach my $param (@params) {
                    if($param < $FIRST_FG_COLOR) {
                        $backend->handle_set_attribute($ATTRIBUTE_FOR_CODE{$param});
                    } elsif($param < $FIRST_BG_COLOR) {
                        $backend->handle_set_fg_color(@{ $FG_COLOR_FOR_CODE{$param} });
                    } elsif($param > $LAST_BG_COLOR) {
                        # XXX freak out
                    } else {
                        $backend->handle_set_bg_color(@{ $BG_COLOR_FOR_CODE{$param} });
                    }
                }
            } else {
                say "unrecognized escape character '$buffer'";
            }
            last;
        }
    } else {
        # XXX do something
    }
}

sub _handle_input {
    my ( $self ) = @_;

    my $pty    = $self->_pty;
    my $buffer = ' ';

    my $backend = $self->backend;

    # XXX grab more than one byte at a time?
    # XXX what about UTF-8?
    while(sysread($pty, $buffer, 1)) {
        use feature qw(say);

        if($buffer eq "\e") {
            _handle_escape_sequence($backend, $pty);
        } elsif($buffer eq "\t") {
            $backend->handle_tab;
        } elsif($buffer eq "\n") {
            $backend->handle_newline;
        } elsif($buffer =~ /[[:print:]]/) {
            $backend->handle_raw_input($buffer);
        } else {
            say ord($buffer);
        }
    }
}

sub wait {
    my ( $self ) = @_;

    croak "No background process running" unless defined $self->_background_pid;

    $self->_handle_input;

    waitpid $self->_background_pid, 0;
    $self->_background_pid(undef);
    return;
}

sub attach {
    my ( $self ) = @_;

    my $pty   = $self->_pty;
    my $slave = $pty->slave;

    $pty->make_slave_controlling_terminal;
    $slave->set_raw;

    close $pty;

    $slave->clone_winsize_from(\*STDIN);

    open STDIN,  '<&', $slave;
    open STDOUT, '>&', $slave;
    open STDERR, '>&', $slave;

    # XXX 0 for pixel values (for now)
    #SetTerminalSize($self->width, $self->height, 0, 0);

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

L<Term::Emulator> exists so that Perl programs may run child
programs in a pseudo-terminal environment and record what they're
doing.  This could be recording a text-based description, creating
a PNG snapshot of the terminal's state at the end of the program,
or even creating an animated GIF showing the change in terminal state
over the course of the execution.  You could even use this module to
write your own graphical terminal emulator in Perl!

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

=head1 RATIONALE

The reason I decided to write this module was as a debugging tool for running Vim
in a pseudo-terminal when using it in an automated fashion.  I'm hoping that others
find other uses for it.

=cut
