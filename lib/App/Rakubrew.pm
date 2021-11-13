package App::Rakubrew;
use strict;
use warnings;
use 5.010;
our $VERSION = '22';

use Encode::Locale qw(env);
if (-t) {
    binmode(STDIN, ":encoding(console_in)");
    binmode(STDOUT, ":encoding(console_out)");
    binmode(STDERR, ":encoding(console_out)");
}
use FindBin qw($RealBin);
use File::Path qw(remove_tree);
use File::Spec::Functions qw(catfile catdir splitpath updir rel2abs);

use App::Rakubrew::Build;
use App::Rakubrew::Config;
use App::Rakubrew::Download;
use App::Rakubrew::Shell;
use App::Rakubrew::Tools;
use App::Rakubrew::Update;
use App::Rakubrew::Variables;
use App::Rakubrew::VersionHandling;

sub new {
    my ($class, @argv) = @_;
    my %opt = (
        args => \@argv,
    );
    my $self = bless \%opt, $class;
    return $self;
}

sub run_script {
    my ($self) = @_;
    my @args = @{$self->{args}};

    sub _cant_access_home {
        say STDERR "Can't create rakubrew home directory in $prefix";
        say STDERR "Probably rakubrew was denied access. You can either change that folder to be writable";
        say STDERR "or set a different rakubrew home directory by setting the `\$RAKUBREW_HOME` environment";
        say STDERR "prior to calling the rakubrew shell hook. ";
        exit 1;
    }

    unless (-d $prefix) {
        _cant_access_home() unless mkdir $prefix;
    }

    mkdir(catdir($prefix, 'bin'))    || _cant_access_home() unless (-d catdir($prefix, 'bin'));
    mkdir(catdir($prefix, 'update')) || _cant_access_home() unless (-d catdir($prefix, 'update'));
    mkdir(catdir($prefix, 'repos'))    || _cant_access_home() unless (-d catdir($prefix, 'repos'));
    mkdir $shim_dir                  || _cant_access_home() unless (-d $shim_dir);
    mkdir $versions_dir              || _cant_access_home() unless (-d $versions_dir);
    mkdir $git_reference             || _cant_access_home() unless (-d $git_reference);

    { # Check whether we are called as a shim and forward if yes.
        my (undef, undef, $prog_name) = splitpath($0);

        # TODO: Mac is also case insensitive. Is this way to compensate for insensitivity safe?
        if ($prog_name ne $brew_name &&
        ($^O !~ /win32/i || $prog_name =~ /^\Q$brew_name\E\z/i)) {
            $self->do_exec($prog_name, \@args);
        }
    }

    { # Detect shell environment and initialize the shell object.
        my $shell = '';
        $shell = $args[1] if @args >= 2 && $args[0] eq 'internal_shell_hook';
        $shell = $args[1] if @args >= 2 && $args[0] eq 'internal_hooked';
        $shell = $args[1] if @args >= 2 && $args[0] eq 'init';
        $self->{hook} = App::Rakubrew::Shell->initialize($shell);
    }

    if (@args >= 2 && $args[0] eq 'internal_hooked') { # The hook is there, all good!
        shift @args; # Remove the hook so processing code below doesn't need to care about it.
        shift @args; # Remove the shell parameter for the same reason.
    }
    elsif (
    get_brew_mode() eq 'env'
        && !(@args && $args[0] eq 'mode' && $args[1] eq 'shim')
        && !(@args && $args[0] eq 'init')
        && !(@args && $args[0] eq 'home')
        && !(@args && $args[0] =~ /^internal_/)
    || @args && $args[0] eq 'shell'
    || @args >= 2 && $args[0] eq 'mode' && $args[1] eq 'env') {
        say STDERR << "EOL";
The shell hook required to run rakubrew in either 'env' mode or with the 'shell' command seems not to be installed.
Run '$brew_name init' for installation instructions if you want to use those features,
or run '$brew_name mode shim' to use 'shim' mode which doesn't require a shell hook.
EOL
        exit 1;
    }

    my $arg = shift(@args) // 'help';

    if ($arg eq 'version' || $arg eq 'current') {
        if (my $c = get_version()) {
            say "Currently running $c"
        } else {
            say STDERR "Not running anything at the moment. Use '$brew_name switch' to set a version";
            exit 1;
        }

    } elsif ($arg eq 'versions' || $arg eq 'list') {
        my $cur = get_version() // '';
        map {
            my $version_line = '';
            $version_line .= 'BROKEN ' if is_version_broken($_);
            $version_line .= $_ eq $cur ? '* ' : '  ';
            $version_line .= $_;
            $version_line .= ' -> ' . get_version_path($_) if is_registered_version($_);
            say $version_line;
        } get_versions();

    } elsif ($arg eq 'global' || $arg eq 'switch') {
        if (!@args) {
            my $version = get_global_version();
            if ($version) {
                say $version;
            }
            else {
                say "$brew_name: no global version configured";
            }
        }
        else {
            $self->match_and_run($args[0], sub {
                set_global_version(shift);
            });
        }

    } elsif ($arg eq 'shell') {
        if (!@args) {
            my $shell_version = get_shell_version();
            if (defined $shell_version) {
                say "$shell_version";
            }
            else {
                say "$brew_name: no shell-specific version configured";
            }
        }
        else {
            my $version = shift @args;
            if ($version ne '--unset') {
                verify_version($version);
            }
        }

    } elsif ($arg eq 'local') {
        validate_brew_mode();
        if (!@args) {
            my $version = get_local_version();
            if ($version) {
                say $version;
            }
            else {
                say "$brew_name: no local version configured for this directory";
            }
        }
        else {
            my $version = shift @args;
            if ($version eq '--unset') {
                set_local_version(undef);
            }
            else {
                $self->match_and_run($version, sub {
                    set_local_version(shift);
                });
            }
        }

    } elsif ($arg eq 'nuke' || $arg eq 'unregister') {
        my $version = shift @args;
        $self->nuke($version);

    } elsif ($arg eq 'rehash') {
        validate_brew_mode();
        rehash();

    } elsif ($arg eq 'list-available' || $arg eq 'available') {
        my ($cur_backend, $cur_rakudo) = split '-', (get_version() // ''), 2;
        $cur_backend //= '';
        $cur_rakudo  //= '';

        my @downloadables = App::Rakubrew::Download::available_precomp_archives();
        say "Available Rakudo versions:";
        map {
            my $ver = $_;
            my $d = (grep {$_->{ver} eq $ver} @downloadables) ? 'D' : ' ';
            my $s = $cur_rakudo eq $ver                       ? '*' : ' ';
            say "$s$d $ver";
        } App::Rakubrew::Build::available_rakudos();
        say '';
        $cur_backend |= '';
        $cur_rakudo |= '';
        say "Available backends:";
        map { say $cur_backend eq $_ ? "* $_" : "  $_" } App::Rakubrew::Variables::available_backends();

    } elsif ($arg eq 'build-rakudo' || $arg eq 'build') {
        my ($impl, $ver, @args) =
            App::Rakubrew::VersionHandling::match_version(@args);
        if (!$ver) {
            my @versions = App::Rakubrew::Build::available_rakudos();
            @versions = grep { /^\d\d\d\d\.\d\d/ } @versions;
            $ver = $versions[-1];
        }

        if ($impl eq "panda") {
            say "panda is discontinued; please use zef (rakubrew build-zef) instead";
        } elsif ($impl eq "zef") {
            my $version = get_version();
            if (!$version) {
                say STDERR "$brew_name: No version set.";
                exit 1;
            }
            App::Rakubrew::Build::build_zef($version);
            # Might have new executables now -> rehash.
            rehash();
            say "Done, built zef for $version";
        } elsif (!exists $impls{$impl}) {
            my $warning = "Cannot build Rakudo with backend '$impl': this backend ";
            if ($impl eq "parrot") {
                $warning .= "is no longer supported.";
            } else {
                $warning .= "does not exist.";
            }
            say $warning;
            exit 1;
        }
        else {
            my $configure_opts = '';
            if (@args && $args[0] =~ /^--configure-opts=/) {
                $configure_opts = shift @args;
                $configure_opts =~ s/^\-\-configure-opts=//;
                $configure_opts =~ s/^'//;
                $configure_opts =~ s/'$//;
            }

            my $name = "$impl-$ver";
            $name = $impl if $impl eq 'moar-blead' && $ver eq 'master';

            if ($impl && $impl eq 'all') {
                for (App::Rakubrew::Variables::available_backends()) {
                    App::Rakubrew::Build::build_impl($_, $ver, $configure_opts);
                }
            } else {
                App::Rakubrew::Build::build_impl($impl, $ver, $configure_opts);
            }

            # Might have new executables now -> rehash.
            rehash();
            if (get_version() eq 'system') {
                set_global_version($name);
            }
            say "Done, $name built";
        }

    } elsif ($arg eq 'triple') {
        my ($rakudo_ver, $nqp_ver, $moar_ver) = @args[0 .. 2];
        my $name = App::Rakubrew::Build::build_triple($rakudo_ver, $nqp_ver, $moar_ver);

        # Might have new executables now -> rehash
        rehash();
        if (get_version() eq 'system') {
            set_global_version($name);
        }
        say "Done, $name built";

    } elsif ($arg eq 'download-rakudo' || $arg eq 'download') {
        my ($impl, $ver, @args) =
            App::Rakubrew::VersionHandling::match_version(@args);

        if (!exists $impls{$impl}) {
            say STDERR "Cannot download Rakudo on '$impl': this backend does not exist.";
            exit 1;
        }

        App::Rakubrew::Download::download_precomp_archive($impl, $ver);

        # Might have new executables now -> rehash
        rehash();
        if (get_version() eq 'system') {
            set_global_version("$impl-$ver");
        }
        say "Done, $impl-$ver installed";
    } elsif ($arg eq 'register') {
        my ($name, $path) = @args[0 .. 1];
        if (!$name || !$path) {
            say STDERR "$brew_name: Need a version name and rakudo installation path";
            exit 1;
        }
        if (version_exists($name)) {
            say STDERR "$brew_name: Version $name already exists";
            exit 1;
        }

        sub invalid {
            my $path = shift;
            say STDERR "$brew_name: No valid rakudo installation found at '$path'";
            exit 1;
        }
        $path = rel2abs($path);
        invalid($path) if !-d $path;
        if (!-f catfile($path, 'bin', 'perl6') && !-f catfile($path, 'bin', 'raku')) {
            $path = catdir($path, 'install');
            if (!-f catfile($path, 'bin', 'perl6') && !-f catfile($path, 'bin', 'raku')) {
                invalid($path);
            }
        }

        spurt(catfile($versions_dir, $name), $path);

    } elsif ($arg eq 'build-zef') {
        my $version = get_version();
        my $zef_version = shift(@args);
        if (!$version) {
            say STDERR "$brew_name: No version set.";
            exit 1;
        }
        say("Building zef ", $zef_version || "latest");
        App::Rakubrew::Build::build_zef($version, $zef_version);
        # Might have new executables now -> rehash
        rehash();
        say "Done, built zef for $version";

    } elsif ($arg eq 'build-panda') {
        say "panda is discontinued; please use zef (rakubrew build-zef) instead";

    } elsif ($arg eq 'exec') {
        my $prog_name = shift @args;
        $self->do_exec($prog_name, \@args);

    } elsif ($arg eq 'which') {
        if (!@args) {
            say STDERR "Usage: $brew_name which <command>";
        }
        else {
            my $version = get_version();
            if (!$version) {
                say STDERR "$brew_name: No version set.";
                exit 1;
            }
            map {say $_} which($args[0], $version);
        }

    } elsif ($arg eq 'whence') {
        if (!@args) {
            say STDERR "Usage: $brew_name whence [--path] <command>";
        }
        else {
            my $param = shift @args;
            my $pathmode = $param eq '--path';
            my $prog = $pathmode ? shift(@args) : $param;
            map {say $_} whence($prog, $pathmode);
        }

    } elsif ($arg eq 'mode') {
        if (!@args) {
            say get_brew_mode();
        }
        else {
            set_brew_mode($args[0]);
        }

    } elsif ($arg eq 'self-upgrade') {
        App::Rakubrew::Update::update();

    } elsif ($arg eq 'init') {
        $self->init(@args);

    } elsif ($arg eq 'home') {
        say $prefix;

    } elsif ($arg eq 'test') {
        my $version = shift @args;
        if (!$version) {
            $self->test(get_version());
        }
        elsif ($version eq 'all') {
            for (get_versions()) {
                $self->test($_);
            }
        } else {
            $self->test($version);
        }
    } elsif ($arg eq 'internal_shell_hook') {
        my $shell = shift @args;
        my $sub   = shift @args;
        if (my $ref = $self->{hook}->can($sub)) {
            $self->{hook}->$sub(@args);
        }

    } elsif ($arg eq 'internal_win_run') {
        my $prog_name = shift @args;
        my $path = which($prog_name, get_version());
        # Do some filetype detection:
        # - .exe/.bat/.cmd              -> return "filename"
        # - .nqp                        -> return "nqp filename"
        # - shebang contains raku|perl6 -> return "raku|perl6 filename"
        # - shebang contains perl       -> return "perl filename"
        # - nothing of the above        -> return "filename" # if we can't
        #                                  figure out what to do with this
        #                                  filename, let Windows have a try.
        # The first line is potentially the shebang. Thus the search for "perl" and/or perl6/raku.
        my ($basename, undef, $suffix) = my_fileparse($prog_name);
        if($suffix =~ /^\Q\.(exe|bat|cmd)\E\z/i) {
            say $path;
        }
        elsif($suffix =~ /^\Q\.nqp\E\z/i) {
            say which('nqp', get_version()).' '.$path;
        }
        else {
            open(my $fh, '<', $path);
            my $first_line = <$fh>;
            close($fh);
            if($first_line =~ /#!.*(perl6|raku)/) {
                say get_raku(get_version()) . ' ' . $path;
            }
            elsif($first_line =~ /#!.*perl/) {
                say 'perl '.$path;
            }
            else {
                say $path;
            }
        }

    } elsif ($arg eq 'internal_update') {
        App::Rakubrew::Update::internal_update(@args);

    } elsif ($arg eq 'rakubrew-version') {
        say "rakubrew v$VERSION Build type: $distro_format OS: $^O";

    } else {
        require Pod::Usage;
        my $help_text = "";
        open my $pod_fh, ">", \$help_text;

        my $verbose = 0;
        @args = grep {
            if ($_ eq '-v' || $_ eq '--verbose') {
                $verbose = 1;
                0;
            }
            else { 1; }
        } @args;

        if ($arg eq 'help' && @args) {
            # the user wants help for a specific command
            # e.g., rakubrew help list
            my $command = $args[ 0 ];
            $command = 'download-rakudo' if $command eq 'download';
            $command = 'build-rakudo'    if $command eq 'build';

            Pod::Usage::pod2usage(
                -exitval   => "NOEXIT",  # do not terminate this script!
                -verbose   => 99,        # 99 = indicate the sections
                -sections  => "COMMAND: " . lc( $command ), # e.g.: COMMAND: list
                -output    => $pod_fh,   # filehandle reference
                -noperldoc => 1          # do not call perldoc
            );

            # some cleanup
            $help_text =~ s/\A[^\n]+\n//s;
            $help_text =~ s/^    //gm;

            $help_text = "Cannot find documentation for [$command]!" if ($help_text =~ /\A\s*\Z/);
        }
        else {
            # Generic help or unknown command
            Pod::Usage::pod2usage(
                -exitval   => "NOEXIT",  # do not terminate this script!
                -verbose   => $verbose ? 2 : 1, # 1 = only SYNOPSIS, 2 = print everything
                -output    => $pod_fh,   # filehandle reference
                -noperldoc => 1          # do not call perldoc
            );
        }

        close $pod_fh;

        my $backends = join '|', App::Rakubrew::Variables::available_backends(), 'all';

        say $help_text;
    }
}

sub match_and_run {
    my ($self, $version, $action) = @_;
    if (!$version) {
        say "Which version do you mean?";
        say "Available builds:";
        map {say} get_versions();
        return;
    }
    if (grep { $_ eq $version } get_versions()) {
        $action->($version);
    }
    else {
        say "Sorry, '$version' not found.";
        my @match = grep { /\Q$version/ } get_versions();
        if (@match) {
            say "Did you mean:";
            say $_ for @match;
        }
    }
}

sub test {
    my ($self, $version) = @_;
    $self->match_and_run($version, sub {
        my $matched = shift;
        verify_version($matched);
        my $v_dir = catdir($versions_dir, $matched);
        if (!-d $v_dir) {
            say STDERR "Version $matched was not built by rakubrew.";
            say STDERR "Refusing to try running spectest there.";
            exit 1;
        }
        chdir catdir($versions_dir, $matched);
        say "Spectesting $matched";
        if (!-f 'Makefile') {
            say STDERR "Can only run spectest in self built Rakudos.";
            say STDERR "This Rakudo is not self built.";
            exit 1;
        }
        run(App::Rakubrew::Build::determine_make($matched), 'spectest');
    });
}

sub nuke {
    my ($self, $version) = @_;
    $self->match_and_run($version, sub {
        my $matched = shift;
        if (is_registered_version($matched)) {
            say "Unregistering $matched";
            unlink(catfile($versions_dir, $matched));
        }
        elsif ($matched eq 'system') {
            say 'I refuse to nuke system Raku!';
            exit 1;
        }
        elsif ($matched eq get_version()) {
            say "$matched is currently active. I refuse to nuke.";
            exit 1;
        }
        else {
            say "Nuking $matched";
            remove_tree(catdir($versions_dir, $matched));
        }
    });
    # Might have lost executables -> rehash
    rehash();
}

sub init {
    my $self = shift;
    my $brew_exec = catfile($RealBin, $brew_name);
    if (@_) {
        # We have an argument. That has to be the shell.
        # We already retrieved the shell above, so no need to look at the passed argument here again.
        say $self->{hook}->get_init_code;
    }
    else {
        say $self->{hook}->install_note;
    }
}

sub do_exec {
    my ($self, $program, $args) = @_;

    my $target = which($program, get_version());
    
    # Run.
    exec { $target } ($target, @$args);
    die "Executing $target failed with: $!";
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

App::Rakubrew - Raku environment manager

=head1 DESCRIPTION

A tool to manage multiple Rakudo installations.

See L<rakubrew.org|https://rakubrew.org/>.

=head1 AUTHOR

Patrick Böker C<< <patrickb@cpan.org> >>
Tadeusz Sośnierz C<< <tadzik@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2020 by Patrick Böker.

This is free software, licensed under:

  The MIT (X11) License

