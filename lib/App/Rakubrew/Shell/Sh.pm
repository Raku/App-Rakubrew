package App::Rakubrew::Shell::Sh;
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
    1;
}

sub install_note {
    return <<EOT;
Load $brew_name automatically in the `sh` shell by adding

  eval "\$($brew_exec init Sh)"

to ~/.profile.
This can be easily done using:

  echo 'eval "\$($brew_exec init auto)"' >> ~/.profile

Note that this enables rakubrew *only* in login shells.
To get rakubrew working in all shells, you need the following:

  echo 'export ENV=~/.shrc' >> ~/.profile
  echo 'eval "\$($brew_exec init Sh)"' >> ~/.shrc

Make sure the `ENV` is not already set to point to some other file.
EOT
}

sub get_init_code {
    my $self = shift;
    my $path = $ENV{PATH};
    $path = $self->clean_path($path);
    if (get_brew_mode() eq 'env') {
        if (get_global_version() && get_global_version() ne 'system') {
            $path = join(':', get_bin_paths(get_global_version()), $path);
        }
    }
    else { # get_brew_mode() eq 'shim'
        $path = join(':', $shim_dir, $path);
    }

    return <<EOT;
export PATH="$path"
$brew_name() {
    command $brew_exec internal_hooked Sh "\$@" &&
    eval "`command $brew_exec internal_shell_hook Sh post_call_eval "\$@"`"
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
    return "export PATH=\"$path\"";
}

sub get_shell_setter_code {
    my $self = shift;
    my $version = shift;
    return "export $env_var=\"$version\"";
}

sub get_shell_unsetter_code {
    my $self = shift;
    return "unset $env_var";
}

1;

