package App::Rakubrew::Build;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw();

use strict;
use warnings;
use 5.010;
use File::Copy::Recursive;
use File::Spec::Functions qw(catdir updir);
use File::Temp qw/ tempdir /;
use Cwd qw(cwd);
use App::Rakubrew::Variables;
use App::Rakubrew::Tools;
use App::Rakubrew::VersionHandling;

sub _get_temp_dir {
    # Rakudo is currently not able to be built in a directory with spaces in
    # its path.
    # Because the default rakubrew directory on MacOS contains a path we build
    # in a temporary directory that usually does not have spaces in its path
    # on MacOS.

    my $dir_tmpl = 'rakubrew_build_XXXXXXXXXX';

    my $dir;

    if ($^O eq 'darwin') {
        $dir = $ENV{TMPDIR};
        $dir = tempdir( $dir_tmpl, DIR => $ENV{TMPDIR} );
    }
    elsif ($^O eq 'win32') {
        # Not in use.
        die "This should never happen.";
    }
    else {
        # Not in use.
        die "This should never happen.";
        # First try /tmp. If that's not accessible, try default temp directory.
        if (-d '/tmp') {
            $dir = tempdir( $dir_tmpl, DIR => '/tmp' );
        }
        else {
            $dir = tempdir( $dir_tmpl, DIR => 1 );
        }
    }

    if (index($dir, ' ') != -1) {
        say STDERR "Unable to find a temporary directory not containing a space.";
        say STDERR "Rakudo currently can't be built in a directory wit spaces.";
        say STDERR "Aborting.";
        exit 1;
    }

    return $dir;
}

sub _get_git_cache_option {
    qx|$PERL5 Configure.pl --help --git-cache-dir=$git_reference|;
    if ( $? >> 8 == 0 ) {
        return "--git-cache-dir=\"$git_reference\"";
    }
    qx|$PERL5 Configure.pl --help --git-reference=$git_reference|;
    if ( $? >> 8 == 0 ) {
        return "--git-reference=\"$git_reference\"";
    }
    return "";
}

sub _get_relocatable_option {
    qx|$PERL5 Configure.pl --help --relocatable|;
    if ( $? >> 8 == 0 ) {
        return "--relocatable";
    }
    say STDERR "The current rakubrew setup requires Rakudo to be relocated, but the";
    say STDERR "Rakudo you selected to be built does not support the `--relocatable`";
    say STDERR "option yet. Try building a newer Rakudo.";
    exit 1;
}

sub available_rakudos {
    my @output = qx|$GIT ls-remote --tags $git_repos{rakudo}|;
    my @tags = grep(m{refs/tags/([^\^]+)\^\{\}}, @output);
    @tags = map(m{tags/([^\^]+)\^}, @tags);
    @tags = grep(/^\d/, @tags);
    return sort(@tags), 'master';
}

sub build_impl {
    my ($impl, $ver, $configure_opts) = @_;

    my $name = "$impl-$ver";
    $name = $impl if $impl eq 'moar-blead' && $ver eq 'master';

    if ($^O eq 'darwin') {
        chdir _get_temp_dir();
    }
    else {
        chdir $versions_dir;
    }

    unless (-d $name) {
        for(@{$impls{$impl}{need_repo}}) {
            update_git_reference($_);
        }
        run "$GIT clone --reference \"$git_reference/rakudo\" $git_repos{rakudo} $name";
    }
    chdir $name;
    run "$GIT fetch";
    # when people say 'build somebranch', they usually mean 'build origin/somebranch'
    my $ver_to_checkout = $ver;
    eval {
        run "$GIT rev-parse -q --verify origin/$ver";
        $ver_to_checkout = "origin/$ver";
    };
    run "$GIT checkout -q $ver_to_checkout";

    $configure_opts .= ' ' . _get_git_cache_option;
    $configure_opts .= ' ' . _get_relocatable_option() if $^O eq 'darwin';
    run $impls{$impl}{configure} . " $configure_opts";

    if ($^O eq 'darwin') {
        # This will write into an existing directory if that exists.
        # This might actually just work.
        my $destdir = catdir($versions_dir, $name);
        say "Moving installation to target directory";
        local $File::Copy::Recursive::RMTrgFil = 1;
        File::Copy::Recursive::dirmove($name, $destdir) or die "Can't move installation: $!";
    }
}

sub determine_make {
    my $makefile = shift;
    $makefile = slurp($makefile);

    if($makefile =~ /^MAKE\s*=\s*(\w+)\s*$/m) {
        return $1;
    }
    else {
        say STDERR "Couldn't determine correct make program. Aborting.";
        exit 1;
    }
}

sub build_triple {
    my ($rakudo_ver, $nqp_ver, $moar_ver) = @_;
    my $impl = "moar";
    $rakudo_ver //= 'HEAD';
    $nqp_ver //= 'HEAD';
    $moar_ver //= 'HEAD';

    my $name = "$impl-$rakudo_ver-$nqp_ver-$moar_ver";

    my $configure_opts = '--make-install'
        . ' --prefix=' .catdir($versions_dir, $name, 'install')
        . ' ' . _get_git_cache_option;

    if ($^O eq 'darwin') {
        chdir _get_temp_dir();
    }
    else {
        chdir $versions_dir;
    }

    my $prefix = catdir($versions_dir, $name, 'install');

    unless (-d $name) {
        update_git_reference('rakudo');
        run "$GIT clone --reference \"$git_reference/rakudo\" $git_repos{rakudo} $name";
    }
    chdir $name;
    run "$GIT pull";
    run "$GIT checkout $rakudo_ver";

    $configure_opts .= ' ' . _get_relocatable_option() if $^O eq 'darwin';

    if (-e 'Makefile') {
        run(determine_make('Makefile'), 'install');
    }

    unless (-d "nqp") {
        update_git_reference('nqp');
        run "$GIT clone --reference \"$git_reference/nqp\" $git_repos{nqp}";
    }
    chdir "nqp";
    run "$GIT pull";
    run "$GIT checkout $nqp_ver";

    unless (-d "MoarVM") {
        update_git_reference('MoarVM');
        run "$GIT clone --reference \"$git_reference/MoarVM\" $git_repos{MoarVM}";
    }
    chdir "MoarVM";
    run "$GIT pull";
    run "$GIT checkout $moar_ver";

    run "$PERL5 Configure.pl " . $configure_opts;

    chdir updir();
    run "$PERL5 Configure.pl --backend=moar " . $configure_opts;

    chdir updir();
    run "$PERL5 Configure.pl --backend=moar " . $configure_opts;

    if (-d 'zef') {
        say "Updating zef as well";
        build_zef($name);
    }

    if ($^O eq 'darwin') {
        # This will write into an existing directory if that exists.
        # This might actually just work.
        my $destdir = catdir($versions_dir, $name);
        say "Moving installation to target directory";
        local $File::Copy::Recursive::RMTrgFil = 1;
        File::Copy::Recursive::dirmove($name, $destdir) or die "Can't move installation: $!";
    }

    return $name;
}

sub build_zef {
    my $version = shift;
    chdir catdir($versions_dir, $version);
    unless (-d 'zef') {
        run "$GIT clone $git_repos{zef}";
    }
    chdir 'zef';
    run "$GIT pull -q";
    run "$GIT checkout";
    run get_raku($version) . " -Ilib bin/zef test .";
    run get_raku($version) . " -Ilib bin/zef --/test --force install .";
}

sub update_git_reference {
    my $repo = shift;
    my $back = cwd();
    print "Update git reference: $repo\n";
    chdir $git_reference;
    unless (-d $repo) {
        run "$GIT clone --bare $git_repos{$repo} $repo";
    }
    chdir $repo;
    run "$GIT fetch";
    chdir $back;
}

sub available_backends {
    map {$_->{name}} sort {$a->{weight} <=> $b->{weight}} values %impls;
}


1;

