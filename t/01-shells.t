use strict; # -*- mode:cperl -*-
use warnings;

use Test::More;
use App::Rakubrew::Shell;

for my $shell_name ( qw(Ash Bash Cmd Fish PowerShell Sh Tcsh Zsh) ) {
  my $sh = App::Rakubrew::Shell->initialize( $shell_name );
  ok( $sh, "$shell_name can be created" );
  like( $sh->install_note, qr/$shell_name/, "Instructions for $shell_name include name of shell" ); 
}

done_testing;
