package App::Rakubrew::Shell::Bash;
use App::Rakubrew::Shell;
our @ISA = "App::Rakubrew::Shell";
use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catfile catdir splitpath);
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
    my $brew_exec = catfile($RealBin, $brew_name);

    return <<EOT;
Load $brew_name automatically in `bash` by adding

  eval "\$($brew_exec init Bash)"

to ~/.bashrc.
This can be easily done using:

  echo 'eval "\$($brew_exec init Bash)"' >> ~/.bashrc
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

    my $brew_exec = catfile($RealBin, $brew_name);

    return <<EOT;
export PATH="$path"
$brew_name() {
    command $brew_exec internal_hooked Bash "\$@" &&
    eval "`command $brew_exec internal_shell_hook Bash post_call_eval "\$@"`"
}
_${brew_name}_completions() {
    COMPREPLY=(\$(command $brew_exec internal_shell_hook Bash completions \$COMP_CWORD \$COMP_LINE))
    \$(command $brew_exec internal_shell_hook Bash completion_options \$COMP_CWORD \$COMP_LINE)
}
complete -F _${brew_name}_completions $brew_name
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
    my @words = @_;
    shift @words; # remove command name

    my @completions = $self->get_completions($index - 1, @words);
    say join(' ', @completions);
}

sub completion_options {
    my $self = shift;
    my $index = shift;
    my @words = @_;

    if($index == 3 && $words[1] eq 'register') {
        say 'compopt -o nospace';
    }
    else {
        say '';
    }
}

1;

