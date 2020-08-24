package App::Rakubrew::Shell::Sh;
use App::Rakubrew::Shell;
our @ISA = "App::Rakubrew::Shell";
use strict;
use warnings;
use 5.010;

use App::Rakubrew::Variables;
use App::Rakubrew::Tools;
use App::Rakubrew::VersionHandling;
use App::Rakubrew::Build;

sub supports_hooking {
    my $self = shift;
    1;
}

sub install_note {
    my $text = <<EOT;
Load $brew_name automatically in POSIX compatible shells (ash, dash, ksh and
similar) by adding

  eval "\$($brew_exec init Sh)"

to ~/.profile.
This can be easily done using:

  echo 'eval "\$($brew_exec init Sh)"' >> ~/.profile

Note that this enables rakubrew *only* in login shells.
To get rakubrew also working in non-login shells, you need the following:

  echo 'export ENV=~/.shrc' >> ~/.profile
  echo 'eval "\$($brew_exec init Sh)"' >> ~/.shrc

Make sure that `ENV` is not already set to point to some other file.
EOT

    if ($prefix =~ / /) {
        $text .= <<EOW;

================================ WARNING ======================================

rakubrews home directory is currently

  $prefix

That folder contains spaces. This will break building rakudos as the build
system currently doesn't work in such a path. You can work around this problem
by changing that folder to a directory without spaces. Do so by putting

  export RAKUBREW_HOME=/some/folder/without/space/rakubrew

in your `~/.profile` file.
EOW
    }
    return $text;
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

