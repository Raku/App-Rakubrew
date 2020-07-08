package App::Rakubrew::Shell::Zsh;
use App::Rakubrew::Shell;
our @ISA = "App::Rakubrew::Shell";
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catfile);

use App::Rakubrew::Variables;
use App::Rakubrew::Tools;
use App::Rakubrew::VersionHandling;
use App::Rakubrew::Build;

sub supports_hooking {
    my $self = shift;
    1;
}

sub install_note {
    my $rc_file = qw( .zshrc );
    if ( exists $ENV{ZDOTDIR} ) {
        $rc_file = catfile( $ENV{ZDOTDIR}, $rc_file );
    }

    my $text = <<EOT;
Load $brew_name automatically in `zsh` by adding

  eval "\$($brew_exec init Zsh)"

to ~/$rc_file.
This can be easily done using:

  echo 'eval "\$($brew_exec init Zsh)"' >> ~/$rc_file
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

in your `~/$rc_file` file *before* the `eval` line.
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
    command $brew_exec internal_hooked Zsh "\$@" &&
    eval "`command $brew_exec internal_shell_hook Zsh post_call_eval "\$@"`"
}

compctl -K _${brew_name}_completions -x 'p[2] w[1,register]' -/ -- $brew_name

_${brew_name}_completions() {
    local WORDS POS RESULT
    read -cA WORDS
    read -cn POS
    reply=(\$(command $brew_exec internal_shell_hook Zsh completions \$POS \$WORDS))
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

sub completions {
    my $self = shift;
    my $index = shift;
    $index--; # We want 0 based
    my @words = @_;

    # Strip command name.
    while (@words > 0) {
        my $word = shift @words;
        $index--;
        last if $word =~ /(^|\W)$brew_name$/;
    }

    my @completions = $self->get_completions($index, @words);
    say join(' ', @completions);
}

1;

