package App::Rakubrew::Shell::Cmd;
use App::Rakubrew::Shell;
our @ISA = "App::Rakubrew::Shell";
use strict;
use warnings;
use 5.010;

use App::Rakubrew::Variables;
use App::Rakubrew::Tools;
use App::Rakubrew::VersionHandling;
use App::Rakubrew::Build;
use App::Rakubrew::Config;

# https://superuser.com/a/302553

sub supports_hooking {
    my $self = shift;
    1;
}

sub install_note {
    # The autorun guard to prevent endless loops is based on this StackOverflow
    # answer: https://stackoverflow.com/a/57451662/1975049

    my $text = <<EOT;
To load $brew_name in CMD automatically you have to do two things:

1. Check that you don't already have a CMD autorun script set.

    reg query "HKCU\\Software\\Microsoft\\Command Processor" /v AutoRun

  If you don't have an autorun script set (the above command returns an error) you can set one using:

    reg add "HKCU\\Software\\Microsoft\\Command Processor" /v AutoRun /t REG_EXPAND_SZ /d \\""\%"USERPROFILE"\%\\Documents\\CMD_profile.cmd"\\" /f

2. Add the following code to the end of the autorun script you linked in step 1:

    \@echo off
    setlocal EnableDelayedExpansion
    set "cmd=!cmdcmdline!"
    if "!cmd!" == "!cmd:/=!" (
        endlocal
        FOR /f "delims=" \%\%i in ('"$brew_exec" init Cmd') do \@\%\%i
    )

  You can easily do that from a CMD prompt using the following command:

    (
    echo \@echo off
    echo setlocal EnableDelayedExpansion
    echo set "cmd=!cmdcmdline!"
    echo if "!cmd!" == "!cmd:/=!" ^(
    echo     endlocal
    echo     FOR /f "delims=" \%\%i in ^('"$brew_exec" init Cmd'^) do \@\%\%i
    echo ^)
    ) >> "\%USERPROFILE\%\\Documents\\CMD_profile.cmd"

  If you use a different autorun script location, replace the path in the command above.

(Note that the above does *not* enable auto-loading in PowerShell, that needs a
separate installation procedure. Call `$brew_exec init` in a PowerShell window
for respective installation instructions.)
EOT

    if ($prefix =~ / /) {
        $text .= <<EOW;

=================================== WARNING ==================================

rakubrews home directory is currently

  $prefix

That folder contains spaces. This will break building rakudos as the build
system currently doesn't work in such a path. You can work around this problem
by changing that folder to a directory without spaces. Do so by putting

  set RAKUBREW_HOME=/some/folder/without/space/rakubrew

in your profile file *before* the other code.
EOW
    }
    return $text;
}

sub get_init_code {
    my $self = shift;
    my $path = $ENV{PATH};
    $path = $self->clean_path($path);
    if (get_brew_mode() eq 'env') {
        my $version = get_global_version();
        if ($version && $version ne 'system' && !is_version_broken($version)) {
            $path = join(';', get_bin_paths($version), $path);
        }
    }
    else { # get_brew_mode() eq 'shim'
        $path = join(';', $shim_dir, $path);
    }

    # https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/doskey
    # https://devblogs.microsoft.com/oldnewthing/20120731-00/?p=7003
    # The command that post_call_eval() returns is always a single line, so we can get away with having an empty delimiter.
    # The second for is there to not error on empty lines: https://stackoverflow.com/a/31316333
    return <<EOT;
SET PATH=$path
doskey rakubrew="$brew_exec" internal_hooked Cmd \$* && FOR /f "delims=" \%i in ('"$brew_exec" internal_shell_hook Cmd post_call_eval \$*') do \@\%i
EOT
}

sub post_call_eval {
    my $self = shift;
    $self->print_shellmod_code(@_);
}

sub get_path_setter_code {
    my $self = shift;
    my $path = shift;
    return "SET PATH=$path";
}

sub get_shell_setter_code {
    my $self    = shift;
    my $version = shift;
    return "SET $env_var=$version"
}

sub get_shell_unsetter_code {
    my $self = shift;
    return "UNSET $env_var";
}

1;
