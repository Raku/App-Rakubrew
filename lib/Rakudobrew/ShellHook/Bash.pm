package Rakudobrew::ShellHook::Bash;
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

sub supports_hooking {
    my $self = shift;
    1;
}

sub install_note {
    my @profiles = qw( .bash_profile .profile );
    my @existing_profiles = grep { -f catfile( $ENV{'HOME'}, $_ ) } @profiles;
    my $profile = @existing_profiles ? $existing_profiles[0] : $profiles[0];

    my $brew_exec = catfile($RealBin, $brew_name);

    return <<EOT;
Load $brew_name automatically by adding

  eval "\$($brew_exec init Bash)"

to ~/$profile.
This can be easily done using:

  echo 'eval "\$($brew_exec init Bash)"' >> ~/$profile
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
    command $brew_name internal_hooked Bash "\$@" &&
    eval "`command $brew_name internal_shell_hook Bash post_call_eval "\$@"`"
}
_${brew_name}_completions() {
    COMPREPLY=(\$(command $brew_name internal_shell_hook Bash completions \$COMP_CWORD \$COMP_LINE))
    \$(command $brew_name internal_shell_hook Bash completion_options \$COMP_CWORD \$COMP_LINE)
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

