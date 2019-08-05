package Rakudobrew::ShellHook;
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catdir catfile updir splitpath);
use Cwd qw(cwd);
use Rakudobrew::Variables;
use Rakudobrew::Tools;
use Rakudobrew::VersionHandling;

my $shell_hook;

sub initialize {
    my $class = shift;
    my $shell = shift;

    if (!grep(/^\Q$shell\E$/, available_hooks("Dummy self"))) {
        # No valid shell given. Do autodetection.
        $shell = detect_shell();
    }

    eval "require Rakudobrew::ShellHook::$shell";
    if ($@) {
        die "Loading shell hook failed: " . $@;
    }
    $shell_hook = bless {}, "Rakudobrew::ShellHook::$shell";
    return $shell_hook;
}

sub detect_shell {
    if ($^O =~ /win32/i) {
        # https://stackoverflow.com/a/8547234
        my $psmodpath = $ENV{PSMODULEPATH};
        my $userprofile = $ENV{USERPROFILE};
        if (index($psmodpath, $userprofile) == 0) {
            return 'PowerShell';
        }
        else {
            return 'Cmd';
        }
    }
    else {
        my $shell = $ENV{'SHELL'} || '/bin/bash';
        $shell = (splitpath( $shell))[2];
        $shell =~ s/[^a-z]+$//; # remove version numbers
        $shell = ucfirst $shell;

        if (!grep(/^\Q$shell\E$/, available_hooks("Dummy self"))) {
            $shell = 'Bash';
        }

        return $shell;
    }
}

sub get {
    my $self = shift;
    return $shell_hook;
}


sub available_hooks {
    my $self = shift;
    my @available_shell_hooks;
    opendir(my $dh, catdir($prefix, 'lib', 'Rakudobrew', 'ShellHook')) or die "$brew_name: lib dir not found";
    while (my $entry = readdir $dh) {
        if ($entry =~ /(.*)\.pm$/) {
            push @available_shell_hooks, $1;
        }
    }
    closedir $dh;
    return @available_shell_hooks;
}

sub print_shellmod_code {
    my $self = shift;
    my @params = @_;
    my $command = shift(@params) // '';
    my $mode = get_brew_mode(1);

    if ($mode eq 'shim') {
        if ($command eq 'shell' && @params) {
            if ($params[0] eq '--unset') {
                say $self->get_shell_unsetter_code();
            }
            else {
                say $self->get_shell_setter_code($params[0]);
            }
        }
        elsif ($command eq 'mode') { # just switched to shim mode
            my $path = $ENV{PATH};
            $path = $self->clean_path($path);
            $path = $shim_dir . ':' . $path;
            say $self->get_path_setter_code($path);
        }
    }
    else { # get_brew_mode() eq 'env'
        my $version = get_version();
        my $path = $ENV{PATH};
        $path = $self->clean_path($path);
        if ($version ne 'system') {
            $path = join(':', get_bin_paths($version), $path);
        }
        if ($path ne $ENV{PATH}) {
            say $self->get_path_setter_code($path);
        }
    }
}

sub clean_path {
    my $self = shift;
    my $path = shift;
    my $also_clean_path = shift;

    my $sep = $^O =~ /win32/i ? ';' : ':';

    my @paths;
    for my $version (get_versions()) {
        push @paths, get_bin_paths($version) if $version ne 'system';
    }
    push @paths, $versions_dir;
    push @paths, $shim_dir;
    push @paths, $also_clean_path if $also_clean_path;
    @paths = map { "\Q$_\E" } @paths;
    my $paths_regex = join "|", @paths;

    my $old_path;
    do {
        $old_path = $path;
        $path =~ s/^($paths_regex)[^$sep]*$//g;
        $path =~ s/^($paths_regex)[^$sep]*$sep//g;
        $path =~ s/$sep($paths_regex)[^$sep]*$//g;
        $path =~ s/$sep($paths_regex)[^$sep]*$sep/$sep/g;
    } until $path eq $old_path;
    return $path;
}

1;
