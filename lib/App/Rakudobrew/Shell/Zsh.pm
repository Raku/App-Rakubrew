package App::Rakudobrew::Shell::Zsh;
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
    # add zsh files in custom paths
    # it should be true that if ZDOTDIR has been set the user
    # wants to use the zsh, but another shell could be
    # in place now
    my @profiles = qw( .zshenv .zshrc .zlogin );
    if ( exists $ENV{ZDOTDIR} ) {
        unshift @profiles, map { catfile( $ENV{ZDOTDIR}, $_ ) } @profiles;
    }
    my @existing_profiles = grep { -f catfile( $ENV{'HOME'}, $_ ) } @profiles;
    my $profile = @existing_profiles ? $existing_profiles[0] : $profiles[0];

    return <<EOT;
Load $brew_name automatically by adding

  eval "\$($brew_exec init Zsh)"

to ~/$profile.
This can be easily done using:

  echo 'eval "\$($brew_exec init Zsh)"' >> ~/$profile
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
    command $brew_name internal_hooked Zsh "\$@" &&
    eval "`command $brew_name internal_shell_hook Zsh post_call_eval "\$@"`"
}

compctl -K _${brew_name}_completions -x 'p[2] w[1,register]' -/ -- $brew_name

_${brew_name}_completions() {
    local WORDS POS RESULT
    read -cA WORDS
    read -cn POS
    reply=(\$(command $brew_name internal_shell_hook Zsh completions \$POS \$WORDS))
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
    while (@words > 0 && !(@words[0] =~ /(^|\W)$brew_name$/) {
        shift @words;
        $index--;
    }

    my @completions = $self->get_completions($index, @words);
    say join(' ', @completions);
}

1;

