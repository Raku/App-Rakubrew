use strict; # -*- mode:cperl -*-
use warnings;

use Test::More;
use App::Rakubrew;
use File::Temp ('tempdir');
use FindBin;
use IPC::Run ('run');

use lib "$FindBin::Bin/../lib";

my @rakubrew = ($^X, "-I$FindBin::Bin/../lib", "$FindBin::Bin/../script/rakubrew", "internal_hooked", "Bash");
my $homedir = tempdir( CLEANUP => 1 );
my $PERL   = $^X;

$ENV{RAKUBREW_HOME} = $homedir;

sub ok_with {
    my $cmd = shift;
    my $pattern = shift;
    my $desc = shift;
    my $out;
    my $success = run([@rakubrew, $cmd], \"", \$out);
    ok( $success, "$cmd succeeds" );
    like( $out, qr/$pattern/, $desc ); 
}

sub spurt {
    my ($file, $cont) = @_;
    open(my $fh, '>', $file);
    say $fh $cont;
    close($fh);
}

sub fake_version {
    my $name = shift;
    my $broken = shift;
    mkdir "$homedir/versions/$name";
    mkdir "$homedir/versions/$name/bin";
    spurt("$homedir/versions/$name/bin/raku", "foo") if !$broken;
}

my $out;
my $err;

ok run([@rakubrew], \"", \$out, \$err), "initializing homedir";
ok run([@rakubrew, "list"], \"", \$out), "list command succeeds";
like $out, qr"system", "list command lists system";

fake_version('moar-2020.01');
ok run([@rakubrew], \"", \$out, \$err), "Having a fake version still allows it to run";

ok run([@rakubrew, "list"], \"", \$out), "list command with fake version succeeds";
like $out, qr"moar-2020.01", "list command lists fake version";

fake_version('moar-2020.02', 1);

ok run([@rakubrew, "init", "Bash"], \"", \$out), "init works with broken version present";

ok run([@rakubrew, "list"], \"", \$out), "list command with broken version succeeds";
like $out, qr"moar-2020.02", "list command lists broken version";
like $out, qr"BROKEN", "broken version is marked as such";

done_testing;
