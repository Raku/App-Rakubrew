package App::Rakudobrew::Shell;
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catdir catfile updir splitpath);
use Cwd qw(cwd);
use App::Rakudobrew::Variables;
use App::Rakudobrew::Tools;
use App::Rakudobrew::VersionHandling;

my $shell_hook;

sub initialize {
    my $class = shift;
    my $shell = shift;

    if (!shell_exists('Dummy self', $shell)) {
        # No valid shell given. Do autodetection.
        $shell = detect_shell();
    }

    eval "require App::Rakudobrew::Shell::$shell";
    if ($@) {
        die "Loading shell hook failed: " . $@;
    }
    $shell_hook = bless {}, "App::Rakudobrew::Shell::$shell";
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

        if (!shell_exists('Dummy self', $shell)) {
            $shell = 'Bash';
        }

        return $shell;
    }
}

sub get {
    my $self = shift;
    return $shell_hook;
}

sub shell_exists {
    my $self = shift;
    my $shell = shift;

    eval "require App::Rakudobrew::Shell::$shell";
    return $@ ? 0 : 1;
}

sub print_shellmod_code {
    my $self = shift;
    my @params = @_;
    my $command = shift(@params) // '';
    my $mode = get_brew_mode(1);

    my $sep = $^O =~ /win32/i ? ';' : ':';

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
            $path = $shim_dir . $sep . $path;
            say $self->get_path_setter_code($path);
        }
    }
    else { # get_brew_mode() eq 'env'
        my $version = get_version();
        my $path = $ENV{PATH};
        $path = $self->clean_path($path);
        if ($version ne 'system') {
            $path = join($sep, get_bin_paths($version), $path);
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

=pod
Returns a list of completion candidates.
This function takes two parameters:
- Index of the word to complete (starting at 0)
- a list of words already entered
=cut
sub get_completions {
    my $self = shift;
    my $index = shift;
    my @words = @_;

    if ($index == 0) {
        my @commands = qw(version current versions list global switch shell local nuke unregister rehash list-available build register build-zef download exec which whence mode self-upgrade triple test);
        my $candidate = $words[0] // '';
        return grep({ substr($_, 0, length($candidate)) eq $candidate } @commands);
    }
    elsif($index == 1 && ($words[0] eq 'global' || $words[0] eq 'switch' || $words[0] eq 'shell' || $words[0] eq 'local' || $words[0] eq 'nuke' || $words[0] eq 'test')) {
        my @versions = get_versions();
        push @versions, 'all'     if $words[0] eq 'test';
        push @versions, '--unset' if $words[0] eq 'shell';
        my $candidate = $words[1] // '';
        return grep({ substr($_, 0, length($candidate)) eq $candidate } @versions);
    }
    elsif($index == 1 && $words[0] eq 'build') {
        my $candidate = $words[1] // '';
        return grep({ substr($_, 0, length($candidate)) eq $candidate } (App::Rakudobrew::Build::available_backends(), 'all'));
    }
    elsif($index == 2 && $words[0] eq 'build') {
        my @installed = get_versions();
        my @installables = grep({ my $x = $_; !grep({ $x eq $_ } @installed) } App::Rakudobrew::Build::available_rakudos());

        my $candidate = $words[3] // '';
        return grep({ substr($_, 0, length($candidate)) eq $candidate } @installables);
    }
    elsif($index == 1 && $words[0] eq 'download') {
        my $candidate = $words[1] // '';
        return grep({ substr($_, 0, length($candidate)) eq $candidate } ('moar'));
    }
    elsif($index == 2 && $words[0] eq 'download') {
        my @installed = get_versions();
        my @installables = map { $_->{ver} } App::Rakudobrew::Download::available_precomp_archives();
        @installables = grep({ my $x = $_; !grep({ $x eq $_ } @installed) } @installables);

        my $candidate = $words[3] // '';
        return grep({ substr($_, 0, length($candidate)) eq $candidate } @installables);
    }
    elsif($index == 1 && $words[0] eq 'mode') {
        my @modes = qw(env shim);
        my $candidate = $words[2] // '';
        return grep({ substr($_, 0, length($candidate)) eq $candidate } @modes);
    }
    elsif($index == 2 && $words[0] eq 'register') {
        my @completions;

        my $path = $words[2];
        my ($volume, $directories, $file) = splitpath($path);
        $path = catdir($volume, $directories, $file); # Normalize the path
        my $basepath = catdir($volume, $directories);
        opendir(my $dh, $basepath) or return '';
        while (my $entry = readdir $dh) {
            my $candidate = catdir($basepath, $entry);
            next if $entry =~ /^\./;
            next if substr($candidate, 0, length($path)) ne $path;
            next if !-d $candidate;
            $candidate .= '/' if length($candidate) > 0 && substr($candidate, -1) ne '/';
            push @completions, $candidate;
        }
        closedir $dh;
        return @completions;
    }
}

1;
