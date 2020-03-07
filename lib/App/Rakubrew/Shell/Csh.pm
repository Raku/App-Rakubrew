package App::Rakubrew::Shell::Csh;
use App::Rakubrew::Shell;
our @ISA = "App::Rakubrew::Shell";
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catdir splitpath);
use FindBin qw($RealBin $RealScript);

use App::Rakubrew::Variables;
use App::Rakubrew::Tools;
use App::Rakubrew::VersionHandling;
use App::Rakubrew::Build;

sub supports_hooking {
    my $self = shift;
    0;
}

sub install_note {
    my $text = <<EOT;
Load $brew_name automatically in `csh` by adding

  eval "\$($brew_exec init Csh)"

to ~/.cshrc.
This can be easily done using:

  echo 'eval "\$($brew_exec init Csh)"' >> ~/.cshrc
EOT

    if ($prefix =~ / /) {
        $text .= <<EOW;

=================================== WARNING ==================================

rakubrews home directory is currently

  $prefix

That folder contains spaces. This will break building rakudos as the build
system currently doesn't work in such a path. You can work around this problem
by changing that folder to a directory without spaces. Do so by putting

  export RAKUBREW_HOME=/some/folder/without/space/rakubrew

in your `~/.cshrc` file *before* the `eval` line.
EOW
    }
    return $text;
}

sub shell_setenv_msg {
    my $self = shift;
    return <<EOT;
To (un)set a version locally in this running shell session use the following commands:
setenv $env_var YOUR_VERSION # set
unsetenv $env_var            # unset
EOT
}

sub get_init_code {
    my $self = shift;
    my $path = $ENV{PATH};
    $path = App::Rakubrew::Shell::clean_path($path, $RealBin);
    $path = "$RealBin:$path";
    $path = join(':', $shim_dir, $path);
    return <<EOT;
setenv PATH "$path"
EOT

}

1;

