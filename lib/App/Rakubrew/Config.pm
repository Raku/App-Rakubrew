package App::Rakubrew::Config;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw( $distribution_format );

use strict;
use warnings;
use 5.010;

# One of: fatpack, macos, win, cpan
our $distro_format = 'cpan';

