package App::Rakubrew::Shell::Fish;
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
Load $brew_name automatically by adding

  $brew_exec init Fish | source

to ~/.config/fish/config.fish
This can be easily done using:

echo '$brew_exec init Fish | source' >> ~/.config/fish/config.fish
EOT

    if ($prefix =~ / /) {
        $text .= <<EOW;

=================================== WARNING ==================================

rakubrews home directory is currently

  $prefix

That folder contains spaces. This will break building rakudos as the build
system currently doesn't work in such a path. You can work around this problem
by changing that folder to a directory without spaces. Do so by putting

  set -x RAKUBREW_HOME "/some/folder/without/space/rakubrew"

in your `~/.config/fish/config.fish` file *before* the `source` line.
EOW
    }
    return $text;
}

sub get_init_code {
    my $self = shift;
    my $path = $ENV{PATH};
    $path = $self->clean_path($path);

    my @path_components = split /:/, $path;
    @path_components = map { "'$_'" } @path_components;

    $path =~ s/:/ /g;
    if (get_brew_mode() eq 'env') {
        if (get_global_version() && get_global_version() ne 'system') {
            unshift @path_components, map({ "'$_'" } get_bin_paths(get_global_version()));
        }
    }
    else { # get_brew_mode() eq 'shim'
        unshift @path_components, "'$shim_dir'";
    }

    $path = join(' ', @path_components);

    return <<EOT;
set -x PATH $path

function $brew_name
    command $brew_exec internal_hooked Fish \$argv
    and eval (command $brew_exec internal_shell_hook Fish post_call_eval \$argv)
end

function _${brew_name}_is_not_register
    set args (commandline -poc)
    if [ (count \$args) -eq 3 -a \$args[1] = 'register' ]
        return 1
    else
        return 0
    end
end

complete -c $brew_name -f -n _${brew_name}_is_not_register -a '(command $brew_exec internal_shell_hook Fish completions (commandline -poc) | string split " ")'
EOT

}

sub post_call_eval {
    my $self = shift;
    $self->print_shellmod_code(@_);
}

sub get_path_setter_code {
    my $self = shift;
    my $path = shift;
    my @path_components = split /:/, $path;
    @path_components = map { "'$_'" } @path_components;
    return "set -gx PATH " . join(' ', @path_components);
}

sub get_shell_setter_code {
    my $self = shift;
    my $version = shift;
    return "set -gx $env_var $version";
}

sub get_shell_unsetter_code {
    my $self = shift;
    return "set -ex $env_var";
}

sub completions {
    my $self = shift;
    my @words = @_;

    my @completions = $self->get_completions(@words - 1, @words);
    say join(' ', @completions);
}

1;

