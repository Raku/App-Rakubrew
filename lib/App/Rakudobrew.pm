package App::Rakudobrew;
use strict;
use warnings;
use 5.010;
our $VERSION = '0.01';

use FindBin qw($RealBin);
use File::Path qw(remove_tree);
use File::Spec::Functions qw(catfile catdir splitpath updir);

use App::Rakudobrew::Variables;
use App::Rakudobrew::Tools;
use App::Rakudobrew::VersionHandling;
use App::Rakudobrew::Build;
use App::Rakudobrew::Shell;

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

    mkdir $prefix unless (-d $prefix);

    # Detect incompatible version upgrade and notify user of the breakage.
    {
        my $backends = join '|', App::Rakudobrew::Build::available_backends();
        opendir(my $dh, $prefix);
        my $old_version_found = grep { /^($backends)/ } readdir($dh);
        closedir $dh;

        if ($old_version_found) {
            say STDERR <<"EOS";
You seem to have upgraded rakudobrew to a newer version not compatible with
your current directory layout.

To use the new version you need to completely remove rakudobrew by deleting
$prefix and installing again. See

https://github.com/tadzik/rakudobrew

for installation instructions. You will also need to change the rakudobrew
entry in your shell startup file (~/.profile) a bit. Run `rakudobrew init`
again to see how.

If you don't want to upgrade, but just continue using the old version,
do the following:

cd $prefix && git checkout v1
EOS
            exit 1;
        }
    }

    mkdir $shim_dir      unless (-d $shim_dir);
    mkdir $versions_dir  unless (-d $versions_dir);
    mkdir $git_reference unless (-d $git_reference);

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
        $self->{hook} = App::Rakudobrew::Shell->initialize($shell);
    }

    if (@args >= 2 && $args[0] eq 'internal_hooked') { # The hook is there, all good!
        shift @args; # Remove the hook so processing code below doesn't need to care about it.
        shift @args; # Remove the shell parameter for the same reason.
    }
    elsif (@args && $args[0] =~ /^internal_/  # It's an internal_ method, all good!
    || !@args || $args[0] eq 'init' # We don't want to annoy the user with missing
                                    # hook messages if she might not have even completed
                                    # the installation process.
    || !$self->{hook}->supports_hooking )   # If the shell doesn't support hooks there is no point in whining about it.
    {}
    elsif (get_brew_mode() eq 'env' || @args && $args[0] eq 'shell' || @args >= 2 && $args[0] eq 'mode' && $args[1] eq 'env') {
        say STDERR "The shell hook required to use rakudobrew in 'env' mode or use the 'shell' command seems not to be installed.";
        say STDERR "Run '$brew_name init' for installation instructions.";
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
                set_global_version(shift @args);
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
            if ($version ne '--unset' && !version_exists($version)) {
                say STDERR "$brew_name: version '$version' not installed.";
                exit 1;
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
            $self->match_and_run($args[0], sub {
                set_local_version(shift @args);
            });
        }

    } elsif ($arg eq 'nuke' || $arg eq 'unregister') {
        my $version = shift @args;
        $self->nuke($version);

    } elsif ($arg eq 'rehash') {
        validate_brew_mode();
        rehash();

    } elsif ($arg eq 'list-available') {
        my ($cur_backend, $cur_rakudo) = split '-', (get_version() // ''), 2;
        $cur_backend //= '';
        $cur_rakudo  //= '';
        say "Available Rakudo versions:";
        map { say $cur_rakudo eq $_ ? "* $_" : "  $_" } App::Rakudobrew::Build::available_rakudos();
        say "";
        $cur_backend |= '';
        $cur_rakudo |= '';
        say "Available backends:";
        map { say $cur_backend eq $_ ? "* $_" : "  $_" } App::Rakudobrew::Build::available_backends();

    } elsif ($arg eq 'build') {
        my $impl = shift(@args) // 'moar';
        my $ver = shift @args
            if @args && $args[0] !~ /^--/;

        if (!defined $ver) {
            if ($impl eq 'moar-blead') {
                $ver = 'master';
            }
            else {
                my @versions = App::Rakudobrew::Build::available_rakudos();
                @versions = grep { /^\d\d\d\d\.\d\d/ } @versions;
                $ver = $versions[-1];
            }
        }

        if ($impl eq "panda") {
            say "panda is discontinued; please use zef (rakudobrew build-zef) instead";
        } elsif ($impl eq "zef") {
            my $version = get_version();
            if (!$version) {
                say STDERR "$brew_name: No version set.";
                exit 1;
            }
            App::Rakudobrew::Build::build_zef($version);
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
                for (App::Rakudobrew::Build::available_backends()) {
                    App::Rakudobrew::Build::build_impl($_, $ver, $configure_opts);
                }
            } else {
                App::Rakudobrew::Build::build_impl($impl, $ver, $configure_opts);
            }

            # Might have new executables now -> rehash.
            rehash();
            unless (get_version()) {
                set_global_version($name);
            }
            say "Done, $name built";
        }

    } elsif ($arg eq 'triple') {
        my ($rakudo_ver, $nqp_ver, $moar_ver) = @args[0 .. 2];
        my $name = App::Rakudobrew::Build::build_triple($rakudo_ver, $nqp_ver, $moar_ver);

        # Might have new executables now -> rehash
        rehash();
        unless (get_version()) {
            set_global_version($name);
        }
        say "Done, $name built";

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
        invalid($path) if !-d $path;
        $path = catdir($path, 'install') if !-f catfile($path, 'bin', 'perl6');
        invalid($path) if !-f catdir($path, 'bin', 'perl6');

        spurt(catfile($versions_dir, $name), $path);

    } elsif ($arg eq 'build-zef') {
        my $version = get_version();
        if (!$version) {
            say STDERR "$brew_name: No version set.";
            exit 1;
        }
        App::Rakudobrew::Build::build_zef($version);
        # Might have new executables now -> rehash
        rehash();
        say "Done, built zef for $version";

    } elsif ($arg eq 'build-panda') {
        say "panda is discontinued; please use zef (rakudobrew build-zef) instead";

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
        $self->self_upgrade();

    } elsif ($arg eq 'init') {
        $self->init(@args);

    } elsif ($arg eq 'test') {
        my $version = shift @args;
        if ($version && $version eq 'all') {
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
        # - shebang line contains perl6 -> return "perl6 filename"
        # - shebang line contains perl  -> return "perl filename"
        # - nothing of the above        -> return "filename" # if we can't
        #                                  figure out what to do with this
        #                                  filename, let Windows have a try.
        # The first line is potentially the shebang. Thus the search for "perl" and/or perl6.
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
            if($first_line =~ /#!.*perl6/) {
                say which('perl6', get_version()).' '.$path;
            }
            elsif($first_line =~ /#!.*perl/) {
                say 'perl '.$path;
            }
            else {
                say $path;
            }
        }

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
            # e.g., rakudobrew help list
            my $command = $args[ 0 ];

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

        my $backends = join '|', App::Rakudobrew::Build::available_backends(), 'all';
        $help_text =~ s/<%backends%>/$backends/g;
        $help_text =~ s/<%brew_name%>/$brew_name/g;

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
    opendir(my $dh, $versions_dir);
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

sub self_upgrade {
    my $self = shift;
    chdir $prefix;
    run "$GIT pull";
}

sub test {
    my ($self, $version) = @_;
    $version ||= get_version();
    if (!$version) {
        say STDERR "$brew_name: No version set.";
        exit 1;
    }
    my @match = grep { /\Q$version/ } get_versions();
    my ($matched, $ambiguous) = @match;
    if ($ambiguous) {
        my ($exact) = grep { $_ eq $version } @match;
        if ($exact) {
            ($matched, $ambiguous) = $exact;
        }
    }
    if ($matched and not $ambiguous) {
        say "Spectesting $matched";
        chdir catdir($versions_dir, $matched);
        App::Rakudobrew::Build::make('spectest');
    } elsif (@match) {
        say "Sorry, I'm not sure if you mean:";
        say $_ for @match;
    } else {
        say "Sorry, I have no idea what '$version' is";
        say "Have you run '$brew_name build $version' yet?";
    }
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
            say 'I refuse to nuke system Perl 6!';
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

App::rakudobrew - Perl 6 environment manager

=head1 DESCRIPTION

A tool to manage multiple Rakudo installations.

=head1 AUTHOR

Patrick Böker C<< <patrickz@cpan.org> >>
Tadeusz Sośnierz C<< <tadzik@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2019 by Tadeusz Sośnierz.

This is free software, licensed under:

  The MIT (X11) License

