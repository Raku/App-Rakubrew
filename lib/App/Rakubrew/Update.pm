package App::Rakubrew::Update;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw();

use strict;
use warnings;
use 5.010;
use Furl;
use JSON;
use FindBin qw( $RealBin $RealScript );
use File::Copy;
use File::Spec::Functions qw( catfile catdir );
use Fcntl;

use App::Rakubrew;
use App::Rakubrew::Variables;

my $release_index_url   = 'https://rakubrew.org/releases';
my $download_url_prefix = 'https://rakubrew.org';

my %dl_urls = (
    pp    => "$download_url_prefix/pp",
    win   => "$download_url_prefix/win",
    macos => "$download_url_prefix/macos",
);

sub update {
    my $quiet = shift;

    my $current_rakubrew_file = catfile($RealBin, $RealScript);
    my $own_format = 'pp';
    # TODO Detect our own packaging format, one of: pp, macos, win, cpan
    # Maybe look at $RealScript and see what that outputs on FatPack and PP.

    # check whether this is a CPAN installation. Abort if yes.
    if ($own_format eq 'cpan') {
        say STDERR 'Rakubrew was installed via CPAN, use your CPAN client to update.';
        exit 1;
    }

    my $furl = Furl->new();
	my $release_index = _download_release_index($furl);

    # check version
    if (!($release_index->{latest} > $App::Rakubrew::VERSION)) {
        say 'Rakubrew is up-to-date!';
        exit 0;
    }

    # Display changes
    if (!$quiet) {
        say "Changes:\n";
        for my $change (@{$release_index->{releases}}) {
            next if $change->{version} <= $App::Rakubrew::VERSION;
            say $change->{version} . ':';
            say "    $_" for split(/^/, $change->{changes});
            say '';
        }
        print 'Shall we do the update? [y|N] ';
        my $reply = <STDIN>;
        chomp $reply;
        exit 0 if $reply ne 'y';
    }

    mkdir catdir($prefix, 'update') unless (-d catdir($prefix, 'update'));
    my $update_file = catfile($prefix, 'update', 'rakubrew');

    # delete RAKUBREW_HOME/update/rakubrew
    unlink $update_file;

    # download latest to RAKUBREW_HOME/update/rakubrew
    my $res = $furl->get($dl_urls{$own_format});
    unless ($res->is_success) {
        say STDERR 'Couldn\'t download update. Error: ' . $res->status_line;
        exit 1;
    }
    my $fh;
    if (!sysopen($fh, $update_file, O_WRONLY|O_CREAT|O_EXCL, 0777)) {
        say STDERR "Couldn't write update file to $update_file. Aborting update.";
        exit 1;
    }
    binmode $fh;
    print $fh $res->body;
    close $fh;

    # exec() RAKUBREW_HOME/update/rakubrew internal_update 'path/to/rakubrew'
    { exec($update_file, 'internal_update', $App::Rakubrew::VERSION, $current_rakubrew_file) };
    say STDERR 'Failed to call the downloaded rakubrew executable! Aborting update.';
    exit 1;
}

sub internal_update {
    my ($old_version, $old_rakubrew_file) = @_;

    my $current_script = catfile($RealBin, $RealScript);
    my $update_file = catfile($prefix, 'update', 'rakubrew');
    if ($update_file ne $current_script) {
        say STDERR "'internal_update' was called on a rakubrew ($current_script) that's not $update_file. That's probably wrong and dangerous. Aborting update.";
        exit 1;
    }

    # custom update procedures
    #if ($old_version < 2) {
    #    Do update stuff for version 2.
    #}

    # copy RAKUBREW_HOME/update/rakubrew to 'path/to/rakubrew'
    unlink $old_rakubrew_file;
    my $fh;
    if (!sysopen($fh, $old_rakubrew_file, O_WRONLY|O_CREAT|O_EXCL, 0777)) {
        say STDERR "Couldn't copy update file to $old_rakubrew_file. Rakubrew is broken now. Try manually copying '$update_file' to '$old_rakubrew_file' to get it fixed again.";
        exit 1;
    }
    binmode $fh;
    if (!copy($update_file, $fh)) {
        close $fh;
        unlink $old_rakubrew_file;
        say STDERR "Couldn't copy update file to $old_rakubrew_file. Rakubrew is broken now. Try manually copying '$update_file' to '$old_rakubrew_file' to get it fixed again.";
        exit 1;
    }
    close $fh;
    unlink $update_file;
}

sub _download_release_index {
    my $furl = shift;
    my $res = $furl->get($release_index_url);
    unless ($res->is_success) {
        say STDERR "Couldn\'t fetch release index at $release_index_url. Error: " . $res->status_line;
        exit 1;
    }
    return decode_json($res->content);
}

