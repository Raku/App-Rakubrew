package App::Rakubrew::Download;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw();

use strict;
use warnings;
use 5.010;
use HTTP::Tinyish;
use JSON;
use Config;
use Cwd qw(cwd);
use IO::Uncompress::Unzip qw( $UnzipError );
use File::Path qw( make_path remove_tree );
use File::Copy::Recursive qw( dirmove );
use File::Spec::Functions qw( updir splitpath catfile catdir );
use App::Rakubrew::Variables;
use App::Rakubrew::Tools;
use App::Rakubrew::VersionHandling;

my $release_index_url   = 'https://rakudo.org/dl/rakudo';
my $download_url_prefix = 'https://rakudo.org/dl/rakudo/';

sub download_precomp_archive {
    my ($impl, $ver) = @_;

    my $name = "$impl-$ver";

    chdir $versions_dir;
    if (-d $name) {
        say STDERR "$name is already installed.";
        exit 1;
    }

    my $ht = HTTP::Tinyish->new();

    my @matching_releases = grep {
            $_->{backend} eq $impl && ($ver ? $_->{ver} eq $ver : $_->{latest})
        } _retrieve_releases($ht);

    if (!@matching_releases) {
        say STDERR 'Couldn\'t find a precomp release for OS: "' . _my_platform() . '", architecture: "' . _my_arch() . '"';
        exit 1;
    }
    if (@matching_releases > 1) {
        say STDERR 'Multiple releases found for your architecture. Don\'t know what to install. This shouldn\'t happen.';
        exit 1;
    }

    say 'Downloading ' . $matching_releases[0]->{url};
    my $res = $ht->get($matching_releases[0]->{url});
    unless ($res->{success}) {
        say STDERR "Couldn\'t download release. Error: $res->{status} $res->{reason}";
        exit 1;
    }

    mkdir $name;
    say 'Extracting';
    if (_my_platform() eq 'win') {
        _unzip(\($res->{content}), $name);
    }
    else {
        _untar($res->{content}, $name);
    }

    # Remove top-level rakudo-2020.01 folder and move all files one level up.
    my $back = cwd();
    chdir $name;
    my $rakudo_dir;
    opendir(DIR, '.') || die "Can't open directory: $!\n";
    while (my $file = readdir(DIR)) {
        if (-d $file && $file =~ /^rakudo-/) {
            $rakudo_dir = $file;
            last;
        }
    }
    closedir(DIR);
    unless ($rakudo_dir) {
        say STDERR "Archive didn't look as expected, aborting. Extracted to: $name";
        exit 1;
    }
    dirmove($rakudo_dir, '.');
    rmdir($rakudo_dir);
    chdir $back;
}

sub available_precomp_archives {
    return _retrieve_releases(HTTP::Tinyish->new());
}

sub _retrieve_releases {
    my $ht = shift;
    my $release_index = _download_release_index($ht);
    my @matching_releases =
        sort { $b->{build_rev} cmp $a->{build_rev} }
        grep {
               $_->{name}     eq 'rakudo'
            && $_->{type}     eq 'archive'
            && $_->{platform} eq _my_platform()
            && $_->{arch}     eq _my_arch()
            && $_->{format}   eq (_my_platform() eq 'win' ? 'zip' : 'tar.gz')
        } @$release_index;

    # Filter out older build revisions
    @matching_releases = grep {
        my $this = $_;
        not grep {
               +($_->{build_rev}) > +($this->{build_rev})
            && $_->{name}     eq $this->{name}
            && $_->{type}     eq $this->{type}
            && $_->{platform} eq $this->{platform}
            && $_->{arch}     eq $this->{arch}
            && $_->{format}   eq $this->{format}
            && $_->{ver}      eq $this->{ver};
        } @matching_releases;
    } @matching_releases;

    return @matching_releases;
}

sub _my_platform {
	my %oses = (
		MSWin32 => 'win',
		darwin  => 'macos',
		linux   => 'linux',
		openbsd => 'openbsd',
	);
    return $oses{$^O} // $^O;
}

sub _my_arch {
    my $arch =
        $Config{archname} =~ /x64/i                 ? 'x86_64' :
        $Config{archname} =~ /x86_64/i              ? 'x86_64' :
        $Config{archname} =~ /amd64/i               ? 'x86_64' :
        $Config{archname} =~ /x86/i                 ? 'x86'    :
        $Config{archname} =~ /darwin/i              ? 'x86_64' :
        $Config{archname} =~ /aarch64/i             ? 'arm64'  : # e.g. Raspi >= 2.1 with 64bit OS
        $Config{archname} =~ /arm-linux-gnueabihf/i ? 'armhf'  : # e.g. Raspi >= 2, with 32bit OS
        '';

    unless ($arch) {
        say STDERR 'Couldn\'t detect system architecture. Current arch is: ' . $Config{archname};
        exit 1;
    }
    return $arch;
}

sub _download_release_index {
    my $ht = shift;
    my $res = $ht->get($release_index_url);
    unless ($res->{success}) {
        say STDERR "Couldn\'t fetch release index at $release_index_url. Error: $res->{status} $res->{reason}";
        exit 1;
    }
    return decode_json($res->{content});
}

sub _untar {
    my ($data, $target) = @_;
    my $back = cwd();
    chdir $target;
    open (TAR, '| tar -xz');
    binmode(TAR);
    print TAR $data;
    close TAR;
    chdir $back;
}

sub _unzip {
    my ($data_ref, $target) = @_;

    my $zip = IO::Uncompress::Unzip->new($data_ref);
    unless ($zip) {
        say STDERR "Reading zip file failed. Error: $UnzipError";
        exit 1;
	}

    my $status;
    for ($status = 1; $status > 0; $status = $zip->nextStream()) {
        my $header = $zip->getHeaderInfo();

        my ($vol, $path, $file) = splitpath($header->{Name});

        if (index($path, updir()) != -1) {
            say STDERR 'Found updirs in zip file, this is bad. Aborting.';
            exit 1;
        }

        my $target_dir  = catdir($target, $path);

        unless (-d $target_dir) {
            unless (make_path($target_dir)) {
                say STDERR "Failed to create directory $target_dir. Error: $!";
                exit 1;
            }
        }

        next unless $file;

        my $target_file = catfile($target, $path, $file);

        unless (open(FH, '>', $target_file)) {
            say STDERR "Failed to write $target_file. Error: $!";
            exit 1;
        }
        binmode(FH);

        my $buf;
        while (($status = $zip->read($buf)) > 0) {
            print FH $buf;
        }
        close FH;
    }

    if ($status < 0) {
        say STDERR "Failed to extract archive.";
        exit 1;
    }
}

