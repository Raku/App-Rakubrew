package App::Rakubrew::Shell;
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catdir catfile updir splitpath);
use Try::Tiny;
use App::Rakubrew::Tools;
use App::Rakubrew::Variables;
use App::Rakubrew::VersionHandling;

# Turn on substring-based command line completion where possible contrary to the
# "start of the line completion". I.e., to visualize the difference, 'ver'
# string would result in the following command candidates:
#   SUBSTRING_COMPLETION==1 -> version versions rakubrew-version
#   SUBSTRING_COMPLETION==0 -> version versions
use constant SUBSTRING_COMPLETION => 1;

my $shell_hook;

sub initialize {
    my $class = shift;
    my $shell = shift;

    if (!shell_exists('Dummy self', $shell) || $shell eq 'auto') {
        $shell = detect_shell();
    }

    eval "require App::Rakubrew::Shell::$shell";
    if ($@) {
        die "Loading shell hook failed: " . $@;
    }
    $shell_hook = bless {}, "App::Rakubrew::Shell::$shell";
    return $shell_hook;
}

sub detect_shell {
    if ($^O =~ /win32/i) {
        # https://stackoverflow.com/a/8547234
        my $psmodpath = $ENV{PSMODULEPATH};
        my $userprofile = $ENV{USERPROFILE};
        if (index($psmodpath, $userprofile) >= 0) {
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

        # tcsh claims it's csh on FreeBSD. Try to detect that.
        if ($shell eq 'csh' && $ENV{'tcsh'}) {
            $shell = 'tcsh';
        }

        $shell = ucfirst $shell;

        if (!shell_exists('Dummy self', $shell)) {
            $shell = 'Sh';
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

    eval "require App::Rakubrew::Shell::$shell";
    return $@ ? 0 : 1;
}

sub print_shellmod_code {
    my $self = shift;
    my @params = @_;
    my $command = shift(@params) // '';
    my $mode = get_brew_mode(1);
    my $version;

    my $sep = $^O =~ /win32/i ? ';' : ':';

    if ($command eq 'shell' && @params) {
        $version = $params[0];
        if ($params[0] eq '--unset') {
            say $self->get_shell_unsetter_code();
        }
        elsif (! is_version_broken($params[0])) {
            say $self->get_shell_setter_code($params[0]);
        }
    }
    elsif ($command eq 'mode' && $mode eq 'shim') { # just switched to shim mode
        my $path = $ENV{PATH};
        $path = $self->clean_path($path);
        $path = $shim_dir . $sep . $path;
        say $self->get_path_setter_code($path);
    }
    elsif ($mode eq 'env') {
        $version = get_version();
    }

    if ($mode eq 'env') {
        my $path = $ENV{PATH};
        $path = $self->clean_path($path);

        if ($version ne 'system') {
            if ($version eq '--unset') {
                # Get version ignoring the still set shell version.
                $version = get_version('shell');
            }
            return if is_version_broken($version);
            $path = join($sep, get_bin_paths($version), $path);
        }

        # In env mode several commands require changing PATH, so we just always
        # construct a new PATH and see if it's different.
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
        next if $version eq 'system';
        next if is_version_broken($version);
        try {
            push @paths, get_bin_paths($version);
        }
        catch {
            # Version is broken. So it's likely not in path anyways.
            # -> ignore it
        };
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

# Strips out all elements in arguments array up to and including $bre_name
# command.  The first argument is index where the completion should look for the
# word to be completed.
sub strip_executable {
    my $self = shift;
    my $index = shift;

    my $cmd_pos = 0;
    foreach my $word (@_) {
        ++$cmd_pos;
        --$index;
        last if $word =~ /(^|\W)$brew_name$/;
    }
    return ($index, @_[$cmd_pos..$#_])
}

=pod

Returns a list of completion candidates.
This function takes two parameters:

=over 4

=item * Index of the word to complete, 0-based. If C<-1> is passed then list of all commands is returned.

=item * A list of words already entered

=back

=cut

sub _filter_candidates {
    my $self = shift;
    my $seed = shift;
    return 
        # If a shell preserves ordering then put the prefix-mathing candidates first. I.e. for 'ver' 'version' would
        # precede 'rakudo-version'
        sort { index($a, $seed) cmp index($b, $seed) }
        grep { 
            my $pos = index($_, $seed);
            SUBSTRING_COMPLETION ? $pos >= 0 : $pos == 0
        } @_
}

sub get_completions {
    my $self = shift;
    my ($index, @words) = @_;

    my @commands = qw(version current versions list global switch shell local nuke unregister rehash available list-available build register build-zef download exec which whence mode self-upgrade triple test home rakubrew-version);

    if ($index <= 0) { # if @words is empty then $index == -1
        my $candidate = $index < 0 || !$words[0] ? '' : $words[0];
        my @c = $self->_filter_candidates($candidate, @commands, 'help');
        return @c;
    }
    elsif($index == 1 && ($words[0] eq 'global' || $words[0] eq 'switch' || $words[0] eq 'shell' || $words[0] eq 'local' || $words[0] eq 'nuke' || $words[0] eq 'test')) {
        my @versions = get_versions();
        push @versions, 'all'     if $words[0] eq 'test';
        push @versions, '--unset' if $words[0] eq 'shell';
        my $candidate = $words[1] // '';
        return $self->_filter_candidates($candidate, @versions);
    }
    elsif($index == 1 && $words[0] eq 'exec') {
        my $candidate = $words[1] // '';
        return $self->_filter_candidates($candidate, '--with');
    }
    elsif($index == 2 && $words[0] eq 'exec' && $words[1] eq '--with') {
        my @versions = get_versions();
        my $candidate = $words[2] // '';
        return $self->_filter_candidates($candidate, @versions);
    }
    elsif($index == 1 && $words[0] eq 'build') {
        my $candidate = $words[1] // '';
        return $self->_filter_candidates($candidate, (App::Rakubrew::Variables::available_backends(), 'all'));
    }
    elsif($index == 2 && $words[0] eq 'build') {
        my @installed = map { if ($_ =~ /^\Q$words[1]\E-(.*)$/) {$1} else { () } } get_versions();
        my @installables = grep({ my $able = $_; !grep({ $able eq $_ } @installed) } App::Rakubrew::Build::available_rakudos());
        my $candidate = $words[2] // '';
        return $self->_filter_candidates($candidate, @installables);
    }
    elsif($index == 1 && $words[0] eq 'download') {
        my $candidate = $words[1] // '';
        return $self->_filter_candidates($candidate, ('moar'));
    }
    elsif($index == 2 && $words[0] eq 'download') {
        my @installed = map { if ($_ =~ /^\Q$words[1]\E-(.*)$/) {$1} else { () } } get_versions();
        my @installables = map { $_->{ver} } App::Rakubrew::Download::available_precomp_archives();
        @installables = grep { my $able = $_; !grep({ $able eq $_ } @installed) } @installables;
        my $candidate = $words[2] // '';
        return $self->_filter_candidates($candidate, @installables);
    }
    elsif($index == 1 && $words[0] eq 'mode') {
        my @modes = qw(env shim);
        my $candidate = $words[2] // '';
        return $self->_filter_candidates($candidate, @modes);
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
    elsif($index == 1 && $words[0] eq 'help') {
        my $candidate = $words[1] // '';
        my @topics = @commands;
        push @topics, '--verbose';
        return $self->_filter_candidates($candidate, @topics);
    }
}

1;
