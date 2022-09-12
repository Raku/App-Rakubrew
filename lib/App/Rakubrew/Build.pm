package App::Rakubrew::Build;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw();

use strict;
use warnings;
use 5.010;
use File::Spec::Functions qw(catdir catfile updir);
use IPC::Cmd qw(can_run);
use Cwd qw(cwd);
use App::Rakubrew::Variables;
use App::Rakubrew::Tools;
use App::Rakubrew::VersionHandling;

sub _version_is_at_least {
    my $min_ver = shift;
    my $rakudo_dir = shift;
    my $ver = slurp(catfile($rakudo_dir, 'VERSION'));
    my ($min_year, $min_month, $min_sub);
    my ($year, $month, $sub);
    if ($ver =~ /(\d\d\d\d)\.(\d\d)(?:\.(\d+))?/ ) {
        $year = $1;
        $month = $2;
        $sub = $3 // 0;
    }
    if ($min_ver =~ /(\d\d\d\d)\.(\d\d)(?:\.(\d+))?/ ) {
        $min_year = $1;
        $min_month = $2;
        $min_sub = $3 // 0;
    }

    # If it's not a release by date, it's older.
    return 1 if !$min_year && $year;
    return 0 if $min_year && !$year;

    # If both are really old not by date releases, we are conservative and say
    # the release is older hopefully backwards compatibility will save us.
    return 0 if !$min_year && !$year;

    return 1 if $min_year < $year;
    return 0 if $min_year > $year;
    return 1 if $min_month < $month;
    return 0 if $min_month > $month;
    return 1 if $min_sub < $sub;
    return 0 if $min_sub > $sub;

    return 1; # $min_sub == $sub;
}

sub _get_git_cache_option {
    my $rakudo_dir = shift;
    if ( _version_is_at_least('2020.02', $rakudo_dir) ) {
        return "--git-cache-dir=\"$git_reference\"";
    }
    else {
        return "--git-reference=\"$git_reference\"";
    }
}

sub _get_relocatable_option {
    my $rakudo_dir = shift;
    if ( _version_is_at_least('2019.07', $rakudo_dir) ) {
        return "--relocatable";
    }
    say STDERR "The current rakubrew setup requires Rakudo to be relocated, but the";
    say STDERR "Rakudo you selected to be built does not support the `--relocatable`";
    say STDERR "option yet. Try building a newer Rakudo.";
    exit 1;
}

sub available_rakudos {
    _check_git();

    my @output = qx|$GIT ls-remote --tags $git_repos{rakudo}|;
    my @tags = grep(m{refs/tags/([^\^]+)\^\{\}}, @output);
    @tags = map(m{tags/([^\^]+)\^}, @tags);
    @tags = grep(/^\d/, @tags);
    return sort(@tags), 'master';
}

sub build_impl {
    my ($impl, $ver, $configure_opts) = @_;

    _check_build_dependencies();

    my $name = "$impl-$ver";
    $name = $impl if $impl eq 'moar-blead' && $ver eq 'master';

    if (version_exists($name) && is_registered_version($name)) {
        say STDERR "$name is a registered version. I'm not going to touch it.";
        exit 1;
    }

    chdir $versions_dir;
    unless (version_exists($name)) {
        for(@{$impls{$impl}{need_repo}}) {
            _update_git_reference($_);
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

    $configure_opts .= ' ' . _get_git_cache_option(cwd());
    run $impls{$impl}{configure} . " $configure_opts";
}

sub determine_make {
    my $version = shift;

    my $cmd = get_raku($version) . ' --show-config';
    my $config = qx{$cmd};

    my $make;
    $make = $1 if $config =~ m/::make=(.*)$/m;

    if (!$make) {
        say STDERR "Couldn't determine correct make program. Aborting.";
        exit 1;
    }

    return $make;
}

sub build_triple {
    my ($rakudo_ver, $nqp_ver, $moar_ver) = @_;

    _check_build_dependencies();

    my $impl = "moar";
    $rakudo_ver //= 'HEAD';
    $nqp_ver //= 'HEAD';
    $moar_ver //= 'HEAD';

    my $name = "$impl-$rakudo_ver-$nqp_ver-$moar_ver";

    chdir $versions_dir;

    unless (-d $name) {
        _update_git_reference('rakudo');
        run "$GIT clone --reference \"$git_reference/rakudo\" $git_repos{rakudo} $name";
    }
    chdir $name;
    run "$GIT pull";
    run "$GIT checkout $rakudo_ver";

    my $configure_opts = '--make-install'
        . ' --prefix=' . catdir($versions_dir, $name, 'install')
        . ' ' . _get_git_cache_option(cwd());

    unless (-d "nqp") {
        _update_git_reference('nqp');
        run "$GIT clone --reference \"$git_reference/nqp\" $git_repos{nqp}";
    }
    chdir "nqp";
    run "$GIT pull";
    run "$GIT checkout $nqp_ver";

    unless (-d "MoarVM") {
        _update_git_reference('MoarVM');
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

    return $name;
}

sub _verify_git_branch_exists {
    my $branch = shift;
    return system("$GIT show-ref --verify -q refs/heads/" . $branch) == 0;
}

sub build_zef {
    my $version = shift;
    my $zef_version = shift;

    _check_git();

    if (-d $zef_dir) {
        chdir $zef_dir;
        if (!_verify_git_branch_exists('main')) {
            run "$GIT fetch -q origin main";
        }
        run "$GIT checkout -f -q main && git reset --hard HEAD && $GIT pull -q";
    } else {
        run "$GIT clone $git_repos{zef} $zef_dir";
        chdir $zef_dir;
    }

    my %tags = map  { chomp($_); $_ => 1 } `$GIT tag`;
    if ( $zef_version && !$tags{$zef_version} ) {
        die "Couldn't find version $zef_version, aborting\n";
    }

    if ( $zef_version ) {
        run "$GIT checkout tags/$zef_version";
    } else {
        run "$GIT checkout main";
    }
    run get_raku($version) . " -I. bin/zef test .";
    run get_raku($version) . " -I. bin/zef --/test --force install .";
}

sub _update_git_reference {
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

sub _check_build_dependencies() {
    _check_git();
    _check_perl();
}

sub _check_git {
    if (!can_run($GIT)) {
        say STDERR "Did not find `$GIT` program. That's a requirement for using some rakubrew commmands. Aborting.";
        exit 1;
    }
}

sub _check_perl {
    if (!can_run($PERL5)) {
        say STDERR "Did not find `$PERL5` program. That's a requirement for using some rakubrew commands. Aborting.";
        exit 1;
    }
}

1;

