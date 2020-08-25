package App::Rakubrew::Shell::Tcsh;
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
Load $brew_name automatically in `tcsh` by adding

  eval `$brew_exec init Tcsh`

to ~/.tcshrc.
This can be easily done using:

  echo 'eval `$brew_exec init Tcsh`' >> ~/.tcshrc
EOT

    if ($prefix =~ / /) {
        $text .= <<EOW;

=================================== WARNING ==================================

rakubrews home directory is currently

  $prefix

That folder contains spaces. This will break building rakudos as the build
system currently doesn't work in such a path. You can work around this problem
by changing that folder to a directory without spaces. Do so by putting

  setenv RAKUBREW_HOME /some/folder/without/space/rakubrew

in your `~/.tcshrc` file *before* the `eval` line.
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
    return "setenv PATH \"$path\" && alias $brew_name '$brew_exec internal_hooked Tcsh \\!* && eval \"`$brew_exec internal_shell_hook Tcsh post_call_eval \\!*`\"' && complete $brew_name 'p,*,`$brew_exec internal_shell_hook Tcsh completions \"\$COMMAND_LINE\"`,'";
}

sub post_call_eval {
    my $self = shift;
    $self->print_shellmod_code(@_);
}

sub get_path_setter_code {
    my $self = shift;
    my $path = shift;
    return "setenv PATH \"$path\"";
}

sub get_shell_setter_code {
    my $self = shift;
    my $version = shift;
    return "setenv $env_var \"$version\"";
}

sub get_shell_unsetter_code {
    my $self = shift;
    return "unsetenv $env_var";
}

sub completions {
    my $self = shift;
    my $command = shift;
    my @words = split ' ', $command;
    my $index = @words - 1;
    $index++ if $command =~ / $/;

    my @completions = $self->get_completions($self->strip_executable($index, @words));
    say join(' ', @completions);
}

1;

