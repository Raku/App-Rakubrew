package App::Rakubrew::VersionHandling;
require Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw(
    get_versions
    get_version
    version_exists
    verify_version
    is_version_broken is_version_path_broken
    is_registered_version
    get_version_path clean_version_path
    get_shell_version
    get_local_version set_local_version
    get_global_version set_global_version
    set_brew_mode get_brew_mode get_brew_mode_shell validate_brew_mode
    get_raku
    which whence
    get_bin_paths
    rehash
);

use strict;
use warnings;
use 5.010;
use Encode::Locale qw(env);
use File::Spec::Functions qw(catfile catdir splitdir splitpath catpath canonpath);
use Cwd qw(realpath);
use File::Which qw();
use Try::Tiny;
use App::Rakubrew::Variables;
use App::Rakubrew::Tools;

sub get_versions {
    opendir(my $dh, $versions_dir);
    my @versions = (
        'system',
        sort({ $a cmp $b }
            grep({ /^[^.]/ } readdir($dh)))
    );
    closedir($dh);
    return @versions;
}

sub get_shell_version {
    # Check for shell version by looking for $RAKU_VERSION or $PL6ENV_VERSION the environment.
    if (defined $ENV{$env_var} || defined $ENV{PL6ENV_VERSION}) {
        my $version = env($env_var) // env('PL6ENV_VERSION');
        if (version_exists($version)) {
            return $version;
        }
        else {
            say STDERR "Version '$version' is set via the RAKU_VERSION environment variable.";
            say STDERR "This version is not installed. Ignoring.";
            say STDERR '';
            return undef;
        }
    }
    else {
        return undef;
    }
}

sub get_local_version {
    my ($vol, $path, undef) = splitpath(realpath(), 1);
    my @fragments = splitdir($path);
    while (@fragments) {
        for ($local_filename, '.perl6-version') {
            my $filepath = catpath($vol, catdir(@fragments), $_);
            if (-f $filepath) {
                my $version = trim(slurp($filepath));
                if(version_exists($version)) {
                    return $version;
                }
                else {
                    say STDERR "Version '$version' is given in the";
                    say STDERR "$filepath";
                    say STDERR "file. This version is not installed. Ignoring.";
                    say STDERR '';
                }
            }
        }
        pop @fragments;
    }
    return undef;
}

sub is_version_broken {
    my $version = shift;
    return 0 if $version eq 'system';
    my $path = get_version_path($version, 1);
    return 1 if !$path;
    return 0 if !is_version_path_broken($path);
    return 1;
}

sub is_version_path_broken {
    my $path = shift;
    $path = clean_version_path($path);
    return 1 if !$path;
    for my $exec ('raku', 'raku.bat', 'raku.exe', 'perl6', 'perl6.bat', 'perl6.exe', 'rakudo', 'rakudo.bat', 'rakudo.exe') {
        if (-f catfile($path, 'bin', $exec)) {
            return 0;
        }
    }
    return 1;
}

sub verify_version {
    my $version = shift;

    if (! version_exists($version) ) {
        say STDERR "$brew_name: version '$version' is not installed.";
        exit 1;
    }

    if ( is_version_broken($version) ) {
        say STDERR "Version $version is broken. Refusing to switch to it.";
        exit 1;
    }
}

sub set_local_version {
    my $version = shift;
    if ($version) {
        verify_version($version);
        spurt($local_filename, $version);
    }
    else {
        unlink $local_filename;
        unlink '.perl6-version';
    }
}

sub get_global_version {
    if (!-e catfile($prefix, 'CURRENT')) {
        set_global_version('system', 1);
    }
    my $cur = slurp(catfile($prefix, 'CURRENT'));
    chomp $cur;
    return $cur;
}

sub set_global_version {
    my $version = shift;
    my $silent = shift;
    verify_version($version);
    say "Switching to $version" unless $silent;
    spurt(catfile($prefix, 'CURRENT'), $version);
}

sub get_version {
    my $ignore = shift // '';
    my $version = $ignore eq 'shell' ? undef : get_shell_version();
    return $version if defined $version;
    
    if (get_brew_mode() eq 'shim') {
        # Local version is only supported in shim mode.
        # Check for local version by looking for a `.raku-version` file in the current and parent folders.
        $version = $ignore eq 'local' ? undef : get_local_version();
        return $version if defined $version;
    }

    # Check for global version by looking at `$prefix/CURRENT` (`$prefix/version`)
    return get_global_version();
}

sub set_brew_mode {
    my $mode = shift;
    if ($mode eq 'env') {
        spurt(catfile($prefix, 'MODE'), 'env');
    }
    elsif ($mode eq 'shim') {
        spurt(catfile($prefix, 'MODE'), 'shim');
        rehash();
    }
    else {
        say STDERR "Mode must either be 'env' or 'shim'";
    }
}

sub get_brew_mode {
    my $silent = shift;
    if (!-e catfile($prefix, 'MODE')) {
        spurt(catfile($prefix, 'MODE'), 'env');
    }

    my $mode = trim(slurp(catfile($prefix, 'MODE')));

    if ($mode ne 'env' && $mode ne 'shim') {
        say STDERR 'Invalid mode found: ' . $mode unless $silent;
        say STDERR 'Resetting to env-mode'        unless $silent;
        set_brew_mode('env');
        $mode = 'env';
    }

    return $mode;
}

sub validate_brew_mode {
    if (get_brew_mode() eq 'env') {
        say STDERR "This command is not available in 'env' mode. Switch to to 'shim' mode using '$brew_name mode shim'";
        exit 1;
    }
}

sub version_exists {
    my $version = shift;
    return undef if !defined $version;
    my %versionsMap = map { $_ => 1 } get_versions();
    return exists($versionsMap{$version});
}

sub is_registered_version {
    my $version = shift;
    my $version_file = catdir($versions_dir, $version);
    if (-f $version_file) {
        return 1;
    }
    else {
        return 0;
    }
}

sub clean_version_path {
    my $path = shift;

    my @cands = (catdir($path, 'install'), $path);
    for my $cand (@cands) {
        return $cand if -d catdir($cand, 'bin')
    }
    return undef;
}

sub get_version_path {
    my $version = shift;
    my $no_error = shift || 0;
    my $version_path = catdir($versions_dir, $version);
    $version_path = trim(slurp($version_path)) if -f $version_path;

    $version_path = clean_version_path($version_path);
    return $version_path if $version_path || $no_error;
    die "Installation is broken: $version";
}

sub get_raku {
    my $version = shift;

    return _which('raku', $version) // which('perl6', $version);
}

sub match_version {
    my $impl = shift // 'moar';
    my $ver = shift if @_ && $_[0] !~ /^--/;
    my @args = @_;

    if (!defined $ver) {
        my $version_regex = '^\d\d\d\d\.\d\d(?:\.\d+)?$';
        my $combined_regex = '('
            . join('|', App::Rakubrew::Variables::available_backends())
            . ')-(.+)';
        if ($impl eq 'moar-blead') {
            $ver = 'main';
        }
        elsif ($impl =~ /$combined_regex/) {
            $impl = $1;
            $ver = $2;
        }
        elsif ($impl =~ /$version_regex/) {
            $ver = $impl;
            $impl = 'moar';
        }
        else {
            $ver = '';
        }
    }

    return ($impl, $ver, @args);
}

sub which {
    my $prog = shift;
    my $version = shift;

    my $target = _which($prog, $version);

    if (!$target) {
        say STDERR "$brew_name: $prog: command not found";
        if(whence($prog)) {
            say STDERR <<EOT;

The '$prog' command exists in these Raku versions:
EOT
            map {say STDERR $_} whence($prog);
        }
        exit 1;
    }

    return $target;
}

sub _which {
    my $prog = shift;
    my $version = shift;

    my $target; {
        if ($version eq 'system') {
            my @targets = File::Which::which($prog);
            @targets = map({
                $_ =~ s|\\|/|g;
                $_ = canonpath($_);
            } @targets);

            my $normalized_shim_dir = $shim_dir;
            $normalized_shim_dir =~ s|\\|/|g;
            $normalized_shim_dir = canonpath($normalized_shim_dir);

            @targets = grep({
                my ($volume,$directories,$file) = splitpath( $_ );
                my $target_dir = catpath($volume, $directories);
                $target_dir = canonpath($target_dir);
                $target_dir ne $normalized_shim_dir;
            } @targets);

            $target = $targets[0] if @targets;
        }
        elsif ($^O =~ /win32/i && (my_fileparse($prog))[2] eq '') {
            # If we are on Windows and didn't get a full executable name
            # i.e. the suffix is missing.
            # In this case we look for files with a basename matching
            # the given name and select the best candidate via a preference
            # table.

            sub check_prog_name_match {
                my ($prog, $filename) = @_;
                my ($basename, undef, undef) = my_fileparse($filename);
                return $prog =~ /^\Q$basename\E\z/i;
            }

            my @results = ();
            my @dirs = get_bin_paths($version);
            for my $dir (@dirs) {
                my @files = slurp_dir($dir);
                for my $file (@files) {
                    if(check_prog_name_match($prog, $file)) {
                        push @results, catfile($dir, $file);
                    }
                }
            }
            @results = sort {
                # .exe > .bat > .raku > .p6 > .pl6 > .pl > nothing > rest
                my (undef, undef, $suffix_a) = my_fileparse($a);
                my (undef, undef, $suffix_b) = my_fileparse($b);
                return -1        if $suffix_a eq '.exe'  && $suffix_b ne '.exe';
                return  1        if $suffix_a ne '.exe'  && $suffix_b eq '.exe';
                return $a cmp $b if $suffix_a eq '.exe'  && $suffix_b eq '.exe';
                return -1        if $suffix_a eq '.bat'  && $suffix_b ne '.bat';
                return  1        if $suffix_a ne '.bat'  && $suffix_b eq '.bat';
                return $a cmp $b if $suffix_a eq '.bat'  && $suffix_b eq '.bat';
                return -1        if $suffix_a eq '.raku' && $suffix_b ne '.raku';
                return  1        if $suffix_a ne '.raku' && $suffix_b eq '.raku';
                return $a cmp $b if $suffix_a eq '.raku' && $suffix_b eq '.raku';
                return -1        if $suffix_a eq '.p6'   && $suffix_b ne '.p6';
                return  1        if $suffix_a ne '.p6'   && $suffix_b eq '.p6';
                return $a cmp $b if $suffix_a eq '.p6'   && $suffix_b eq '.p6';
                return -1        if $suffix_a eq '.pl6'  && $suffix_b ne '.pl6';
                return  1        if $suffix_a ne '.pl6'  && $suffix_b eq '.pl6';
                return $a cmp $b if $suffix_a eq '.pl6'  && $suffix_b eq '.pl6';
                return -1        if $suffix_a eq '.pl'   && $suffix_b ne '.pl';
                return  1        if $suffix_a ne '.pl'   && $suffix_b eq '.pl';
                return $a cmp $b if $suffix_a eq '.pl'   && $suffix_b eq '.pl';
                return -1        if $suffix_a eq ''      && $suffix_b ne '';
                return  1        if $suffix_a ne ''      && $suffix_b eq '';
                return $a cmp $b if $suffix_a eq ''      && $suffix_b eq '';
                return $a cmp $b;
            } @results;
            $target = $results[0];
        }
        else {
            my @paths = get_bin_paths($version, $prog);
            for my $path (@paths) {
                if (-e $path) {
                    $target = $path;
                    last;
                }
            }
        }
    }

    return $target;
}

sub whence {
    my $prog = shift;
    my $pathmode = shift // 0;

    my @matches = ();
    for my $version (get_versions()) {
        next if $version eq 'system';
        next if is_version_broken($version);
        for my $path (get_bin_paths($version, $prog)) {
            if (-f $path) {
                if ($pathmode) {
                    push @matches, $path;
                }
                else {
                    push @matches, $version;
                }
                last;
            }
        }
    }
    return @matches;
}

sub get_bin_paths {
    my $version = shift;
    my $program = scalar(shift) || undef;
    my $no_error = shift || undef;
    my $version_path = get_version_path($version, 1);
    return () if $no_error && !$version_path;

    return (
        catfile($version_path, 'bin', $program // ()),
        catfile($version_path, 'share', 'perl6', 'site', 'bin', $program // ()),
    );
}

sub rehash {
    return if get_brew_mode() ne 'shim';

    my @paths = ();
    for my $version (get_versions()) {
        next if $version eq 'system';
        next if is_version_broken($version);
        push @paths, get_bin_paths($version);
    }

    say "Updating shims";

    { # Remove the existing shims.
        opendir(my $dh, $shim_dir);
        while (my $entry = readdir $dh) {
            next if $entry =~ /^\./;
            unlink catfile($shim_dir, $entry);
        }
        closedir $dh;
    }

    my @bins = map { slurp_dir($_) } @paths;

    if ($^O =~ /win32/i) {
        # This wrapper is needed because:
        # - We want rakubrew to work even when the .pl ending is not associated with the perl program and we do not want to put `perl` before every call to a shim.
        # - exec() in perl on Windows behaves differently from running the target program directly (output ends up on the console differently).
        # It retrieves the target executable (only consuming STDOUT of rakubrew) and calls it with the given arguments. STDERR still ends up on the console. The return value is checked and if an error occurs that error values is returned.
        # `IF ERRORLEVEL 1` is true for all exit codes >= 1.
        # See https://stackoverflow.com/a/8254331 for an explanation of the `SETLOCAL` / `ENDLOCAL` mechanics.
        @bins = map { my ($basename, undef, undef) = my_fileparse($_); $basename } @bins;
        @bins = uniq(@bins);
        for (@bins) {
            spurt(catfile($shim_dir, $_.'.bat'), <<EOT);
\@ECHO OFF
SETLOCAL
SET brew_cmd="$brew_exec" internal_win_run \%~n0
FOR /F "delims=" \%\%i IN ('\%brew_cmd\%') DO SET command=\%\%i
IF ERRORLEVEL 1 EXIT /B \%errorlevel\%
ENDLOCAL & "\%command\%" \%*
EOT
        }
    }
    else {
        for (@bins) {
            symlink $0, catfile($shim_dir, $_);
        }
    }
}
