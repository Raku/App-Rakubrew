use strict;
use warnings;

use Test::More;
use App::Rakubrew;
use File::Temp ('tempdir');
use File::Copy;
use FindBin;
use IPC::Run ('run');

use lib "$FindBin::Bin/../lib";

my $rakubrew_exec = $ENV{"RAKUBREW_TEST_EXEC"};

my $PERL   = $^X;
my $homedir = tempdir( CLEANUP => 0 );
$ENV{RAKUBREW_HOME} = $homedir;

my @rakubrew;
my @exec;
if ($rakubrew_exec) {
    @exec = ();
    @rakubrew = ($rakubrew_exec, "internal_hooked", "Bash");
}
else {
    @exec = ($PERL, "-I$FindBin::Bin/../lib");
    @rakubrew = ($PERL, "-I$FindBin::Bin/../lib", "$FindBin::Bin/../script/rakubrew", "internal_hooked", "Bash");
}

sub spurt {
    my ($file, $cont) = @_;
    open(my $fh, '>', $file);
    say $fh $cont;
    close($fh);
}

sub fake_install {
    my $path = shift;
    my $broken = shift;
    mkdir "$path/bin";
    spurt("$path/bin/raku", "foo") if !$broken;
}
sub fake_version {
    my $name = shift;
    my $broken = shift;
    mkdir "$homedir/versions";
    mkdir "$homedir/versions/$name";
    fake_install("$homedir/versions/$name", $broken);
}

sub diff_env {
    my ($leftRef, $rightRef) = @_;
    my @left = @{$leftRef};
    my @right = @{$rightRef};
    @left = sort @left;
    @right = sort @right;
    my ($ls, $rs) = (scalar @left, scalar @right);
    my ($li, $ri) = (0, 0);
    my (@lextra, @rextra);
    while ($li < $ls && $ri < $rs) {
        if ($li >= $ls) {
            push @rextra, $right[$ri];
            $ri++;
        }
        elsif ($ri >= $rs) {
            push @lextra, $left[$li];
            $li++;
        }
        elsif ($left[$li] gt $right[$ri]) {
            push @rextra, $right[$ri];
            $ri++;
        }
        elsif ($left[$li] lt $right[$ri]) {
            push @lextra, $left[$li];
            $li++;
        }
        else {
            $li++;
            $ri++;
        }
    }
    return (\@lextra, \@rextra);
}

my $out;
my $err;

fake_version('moar-2020.01');
my $print_script = "$homedir/versions/moar-2020.01/bin/print-env.pl";
copy("$FindBin::Bin/bin/print-env.pl", $print_script);
chmod 0755, $print_script;

run([@rakubrew, "switch", "moar-2020.01"], \"", \$out, \$err);
run([@rakubrew, "mode", "shim"], \"", \$out, \$err);
run([@exec, "$homedir/shims/print-env.pl"], \"", \$out);

my @inner_env = split("\n", $out);
@inner_env = grep { $_ } @inner_env;

my @outer_env;
for my $key (keys(%ENV)) {
    my $val = $ENV{$key};
    my @vals = split "\n", $val;
    if (@vals > 1) {
        push @outer_env, "$key=$vals[0]";
        shift @vals;
        push @outer_env, $_ for @vals;
    }
    else {
        push @outer_env, "$key=$val";
    }
}

# Ignore __CF_USER_TEXT_ENCODING. That var seems to be added by `exec` itself on MacOS.
# I think I can't do anything about this. Thus ignore.
@inner_env = grep { ! /^__CF_USER_TEXT_ENCODING=/ } @inner_env;
@outer_env = grep { ! /^__CF_USER_TEXT_ENCODING=/ } @outer_env;

my ($missingRef, $excessRef) = diff_env(\@outer_env, \@inner_env);

is_deeply $missingRef, [], "Rakubrew doesn't lose env vars";
is_deeply $excessRef, [], "Rakubrew doesn't add env vars";

done_testing;

