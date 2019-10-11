package App::Rakudobrew::Shell::Sh;
use App::Rakudobrew::Shell;
our @ISA = "App::Rakudobrew::Shell";
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catdir splitpath);
use FindBin qw($RealBin $RealScript);

use App::Rakudobrew::Variables;
use App::Rakudobrew::Tools;
use App::Rakudobrew::VersionHandling;
use App::Rakudobrew::Build;

sub supports_hooking {
    my $self = shift;
    1;
}

sub install_note {
    my $brew_exec = catfile($RealBin, $brew_name);
    return <<EOT;
Load $brew_name automatically by adding

  eval "\$($brew_exec init Sh)"

to ~/.profile.
This can be easily done using:

  echo 'eval "\$($brew_exec init Sh)"' >> ~/.profile
EOT
}

sub get_init_code {
    my $self = shift;
    my $path = $ENV{PATH};
    $path = $self->clean_path($path, $RealBin);
    $path = "$RealBin:$path";
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
    command $brew_name internal_hooked Sh "\$@" &&
    eval "`command $brew_name internal_shell_hook Sh post_call_eval "\$@"`"
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

