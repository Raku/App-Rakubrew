package Rakudobrew::ShellHook::PowerShell;
use Rakudobrew::ShellHook;
our @ISA = "Rakudobrew::ShellHook";
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catfile catdir splitpath);
use FindBin qw($RealBin $RealScript);

use Rakudobrew::Variables;
use Rakudobrew::Tools;
use Rakudobrew::VersionHandling;
use Rakudobrew::Build;

# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes?view=powershell-6
# https://stackoverflow.com/questions/6766722/how-to-modify-parent-scope-variable-using-powershell
# https://superuser.com/questions/886951/run-powershell-script-when-you-open-powershell
# https://www.computerperformance.co.uk/powershell/profile-ps1/

=pod
WARNING:
Setting PATH to a string longer than 2048 chars (4096 on newer systems) can cause the
PATH to be truncated, your PATH being set to the empty string and only become available
again upon reboot and in the worst case cause your system to not boot anymore.
See https://web.archive.org/web/20190519191717/https://software.intel.com/en-us/articles/limitation-to-the-length-of-the-system-path-variable

This problem is smaller for us, because we only modify PATH in the current console, never globally.
=cut

sub supports_hooking {
    my $self = shift;
    1;
}

sub install_note {
    my $brew_exec = catfile($RealBin, $brew_name);
    return <<EOT;
Load $brew_name automatically by adding

  perl $brew_exec init PowerShell | Out-String | Invoke-Expression

to your PowerShell profile.
This can be easily done using:

  Add-Content -Force -Path \$PROFILE -Value 'perl $brew_exec init PowerShell | Out-String | Invoke-Expression'
EOT
}

sub get_init_code {
    my $self = shift;
    my $path = $ENV{PATH};
    $path = $self->clean_path($path, $RealBin);
    $path = "$RealBin;$path";
    if (get_brew_mode() eq 'env') {
        if (get_global_version() && get_global_version() ne 'system') {
            $path = join(';', get_bin_paths(get_global_version()), $path);
        }
    }
    else { # get_brew_mode() eq 'shim'
        $path = join(';', $shim_dir, $path);
    }
    
    my $brew_exec = catfile($RealBin, $brew_name);
    
    return <<EOT;
\$Env:PATH = "$path"
Function $brew_name {
    # TODO: In PowerShell functions do not have return codes. Thus we can not forward the underlying return code.
    # For now we just throw if the actual rakudobrew has a returncode != 0. Maybe come up with a better way?
    perl $brew_exec internal_hooked PowerShell \$args
    if (\$LASTEXITCODE -ne 0) {
        Throw "Rakudobrew failed with exitcode \$LASTEXITCODE"
    }
    \$cmd = perl $brew_exec internal_shell_hook PowerShell post_call_eval \$args | Out-String
    if (\$cmd) {
        Invoke-Expression -Command \$cmd
    }
}
# TODO: \$PSVersionTable.PSVersion is only available from PowerShell 2.0 onward. Either accept that this fails on PS 1 or find a way to guard against that.
if (\$PSVersionTable.PSVersion -ge "5.0.0.0") {
    Register-ArgumentCompleter -Native -CommandName $brew_name -ScriptBlock {
        param(\$commandName, \$argumentString, \$position)
        \$completions = perl $brew_exec internal_shell_hook PowerShell completions "\$position" "\$argumentString" | Out-String
        \$completions = \$completions.trim('\n').Split(' ')
        \$completions | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(\$_, \$_, 'ParameterValue', \$_)
        }
    }
}
EOT
}

sub post_call_eval {
    my $self = shift;
    $self->print_shellmod_code(@_);
}

sub get_path_setter_code {
    my $self = shift;
    my $path = shift;
    return "\$Env:PATH = \"$path\"";
}

sub get_shell_setter_code {
    my $self    = shift;
    my $version = shift;
    return "Set-Variable -Name $env_var -Value \"$version\" -Scope Global";
}

sub get_shell_unsetter_code {
    my $self = shift;
    return "Remove-Variable -Name $env_var -Scope Global";
}

sub completions {
    my $self = shift;
    my $position = shift;
    my $argumentString = join ' ', @_;

    # Check if the cursor is starting a new word (preceding space).
    my $newWord = $position > length($argumentString) ? 1
        : substr($argumentString, $position - 1, $position) eq ' ' ? 1
        : 0;

    # Cut off everything after cursor position.
    $argumentString = substr($argumentString, 0, $position);

    # Chop off trailing space.
    $argumentString = chop($argumentString) if substr($argumentString, 0, length($argumentString) - 1) eq ' ';

    # Remove command name and trailing space from arguments.
    $argumentString =~ s/(^|.*\W)$brew_name(\.bat|\.exe)? ?//;

    my @words = split ' ', $argumentString;
    my $index = @words - 1 + ($newWord ? 1 : 0);

    my @completions = $self->get_completions($index, @words);
    say join(' ', @completions);
}

1;
