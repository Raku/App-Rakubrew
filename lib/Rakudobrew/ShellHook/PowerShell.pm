package Rakudobrew::ShellHook::PowerShell;
use Rakudobrew::ShellHook;
our @ISA = "Rakudobrew::ShellHook";
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catdir splitpath);
use FindBin qw($RealBin $RealScript);

use Rakudobrew::Variables;
use Rakudobrew::Tools;
use Rakudobrew::VersionHandling;
use Rakudobrew::Build;

# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes?view=powershell-6
# https://stackoverflow.com/questions/6766722/how-to-modify-parent-scope-variable-using-powershell
# https://superuser.com/questions/886951/run-powershell-script-when-you-open-powershell
# https://www.computerperformance.co.uk/powershell/profile-ps1/

sub supports_hooking {
    my $self = shift;
    0;
}

sub install_note {
    return <<EOT;
To install $brew_name permanently type the following into your terminal
(only works with an administrative console window):
  [Environment]::SetEnvironmentVariable("PATH", "$RealBin;$shim_dir;\$Env:PATH", "User")
To make use of $brew_name in this session only use
  \$Env:PATH = "$RealBin;$shim_dir;\$Env:PATH"

Using the GUI:
Start -> right click on "Computer" -> Properties -> (Advanced system settings)
-> Advanced -> Environment Variables... ->  System variables
-> select PATH -> Edit... -> prepend "$RealBin;$shim_dir;"

WARNING:
Setting PATH to a string longer than 2048 chars (4096 on newer systems) can cause the
PATH to be truncated, your PATH being set to the empty string and only become available
again upon reboot and in the worst case cause your system to not boot anymore.
See https://web.archive.org/web/20190519191717/https://software.intel.com/en-us/articles/limitation-to-the-length-of-the-system-path-variable
EOT
}

sub shell_setenv_msg {
    my $self = shift;
    return <<EOT;
To (un)set a version locally in this running shell session use the following commands:
\$Env:$env_var="YOUR_VERSION" # set
Remove-Item Env:\\$env_var    # unset
EOT
}

sub get_init_code {
    my $self = shift;
    my $path = $ENV{PATH};
    $path = Rakudobrew::ShellHook::clean_path($path, $RealBin);
    $path = "$RealBin:$path";
    $path = join(':', $shim_dir, $path);
    return <<EOT;
setenv PATH "$path"
EOT

}

1;

