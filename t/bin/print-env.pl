#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

for my $key (sort(keys(%ENV))) {
    my $val = $ENV{$key};
    print "$key=$val\n";
}

