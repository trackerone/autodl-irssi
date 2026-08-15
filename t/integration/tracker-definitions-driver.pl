use 5.008;
use strict;
use warnings;

use Irssi;
use AutodlIrssi::Dirs;
use AutodlIrssi::InternetUtils qw/ decodeJson /;

our $VERSION = '1.0';
our %IRSSI = (
	authors => 'autodl-irssi test harness',
	name => 'tracker-definitions-driver',
	description => 'Offline production tracker-definition parser and reload driver',
	license => 'MPL-1.1',
);

sub slurp_file {
	my $filename = shift;
	open my $fh, '<', $filename or die "Could not open '$filename': $!\n";
	local $/;
	my $data = <$fh>;
	close $fh or die "Could not close '$filename': $!\n";
	return $data;
}

sub assert_equal {
	my ($label, $actual, $expected) = @_;
	$actual = '' unless defined $actual;
	die "$label was '$actual', expected '$expected'\n" unless $actual eq $expected;
}

my $source_metadata_file = $ENV{AUTODL_TRACKER_SOURCE_METADATA};
die "AUTODL_TRACKER_SOURCE_METADATA is required\n"
	unless defined $source_metadata_file && -f $source_metadata_file;
my $source_metadata = decodeJson(slurp_file($source_metadata_file));
my $expected_count = $source_metadata->{tracker_files};
die "Invalid expected tracker count\n"
	unless defined $expected_count && $expected_count =~ /^\d+$/ && $expected_count > 0;

my $tracker_dir = getTrackerFilesDir();
my $tracker_manager = $AutodlIrssi::g->{trackerManager};
my @tracker_files = sort $tracker_manager->getTrackerFiles($tracker_dir);
die "Found " . scalar(@tracker_files) . " tracker files, expected $expected_count\n"
	unless scalar(@tracker_files) == $expected_count;

my $tracker_infos = $tracker_manager->getTrackerInfos($tracker_dir);
die "Parsed " . scalar(@$tracker_infos) . " tracker files, expected $expected_count\n"
	unless scalar(@$tracker_infos) == $expected_count;

my %types;
for my $tracker_info (@$tracker_infos) {
	my $type = $tracker_info->{type};
	die "Parsed tracker has no type\n" unless defined $type && $type ne '';
	die "Duplicate tracker type '$type'\n" if $types{$type}++;
}
die "Found " . scalar(keys %types) . " unique tracker types, expected $expected_count\n"
	unless scalar(keys %types) == $expected_count;

$tracker_manager->reloadTrackerFiles($tracker_dir);
my $loaded_count = $tracker_manager->getNumberOfTrackers();
die "Reloaded $loaded_count tracker types, expected $expected_count\n"
	unless $loaded_count == $expected_count;

my $ptp = $tracker_manager->{announceParsers}{ptp};
die "PassThePopcorn tracker was not loaded\n" unless defined $ptp;
$ptp->writeOption('authkey', 'AUTHKEY');
$ptp->writeOption('torrent_pass', 'TORRENTPASS');
my $ptp_announce = '0:2:0:0:357805:1332009:9k6p:tt24249072:1899875175:1728081334|H.264/MKV/WEB/720p||2023|Last Straw|Last.Straw.2023.REPACK.720p.AMZN.WEB-DL.DDP5.1.H.264-FLUX|thriller,horror';
my $ptp_ti = $ptp->onNewLine($ptp_announce);
die "Current PassThePopcorn announce did not parse\n" unless defined $ptp_ti;
assert_equal('PassThePopcorn torrent name', $ptp_ti->{torrentName}, 'Last.Straw.2023.REPACK.720p.AMZN.WEB-DL.DDP5.1.H.264-FLUX');
assert_equal('PassThePopcorn category', $ptp_ti->{category}, 'Short Film');
assert_equal('PassThePopcorn origin', $ptp_ti->{origin}, 'P2P');
assert_equal('PassThePopcorn size', $ptp_ti->{torrentSize}, '1899875175');
assert_equal('PassThePopcorn URL', $ptp_ti->{torrentUrl}, 'https://passthepopcorn.me/torrents.php?action=download&id=1332009&authkey=AUTHKEY&torrent_pass=TORRENTPASS&key=9k6p');

my $ptp_historical_announce = 'Dirty Rotten Scoundrels [1988] by Frank Oz - x264 / Blu-ray / MKV / 720p - http://passthepopcorn.me/torrents.php?id=10735 / http://passthepopcorn.me/torrents.php?action=download&id=97367 - comedy, crime';
my $ptp_historical_ti = $ptp->onNewLine($ptp_historical_announce);
die "Historical PassThePopcorn announce did not parse\n" unless defined $ptp_historical_ti;
assert_equal('Historical PassThePopcorn URL', $ptp_historical_ti->{torrentUrl}, 'https://passthepopcorn.me/torrents.php?action=download&id=97367&authkey=AUTHKEY&torrent_pass=TORRENTPASS');

my $ptp_freeleech_announce = '1:1:2:1:21108:1332339:ncfe:tt0107426:63996413804:1728081334|BD66/m2ts/Blu-ray/2160p|Dolby Atmos/Dolby Vision|1993|Little Buddha|Little.Buddha.1993.2160p.FRA.UHD.Blu-ray.DV.HDR.HEVC.DTS-HD.MA.5.1|drama,italian';
my $ptp_freeleech_ti = $ptp->onNewLine($ptp_freeleech_announce);
die "PassThePopcorn freeleech announce did not parse\n" unless defined $ptp_freeleech_ti;
assert_equal('PassThePopcorn freeleech flag', $ptp_freeleech_ti->{freeleech}, '1');
assert_equal('PassThePopcorn internal origin', $ptp_freeleech_ti->{origin}, 'Internal');

my $ncore = $tracker_manager->{announceParsers}{nc};
die "nCore tracker was not loaded\n" unless defined $ncore;
assert_equal('nCore short name', $ncore->getTrackerInfo()->{shortName}, 'nC');
my @ncore_servers = map { $_->{name} } @{$ncore->getTrackerInfo()->{servers}};
die "nCore does not use irc.ncore.pro\n" unless grep { $_ eq 'irc.ncore.pro' } @ncore_servers;
die "nCore still uses irc.p2p-network.net\n" if grep { $_ eq 'irc.p2p-network.net' } @ncore_servers;
$ncore->writeOption('passkey', 'PASSKEY');
my $ncore_announce = '[NEW TORRENT in hdser_hun] Sherlock.S01-S04.COMPLETE.1080p.BluRay.DD5.1.x264.HUN.ENG-pcroland > 227.97 GiB in 46F > https://ncore.pro/torrents.php?action=details&id=3119161';
my $ncore_ti = $ncore->onNewLine($ncore_announce);
die "Current nCore announce did not parse\n" unless defined $ncore_ti;
assert_equal('nCore size', $ncore_ti->{torrentSize}, '227.97 GiB');
assert_equal('nCore URL', $ncore_ti->{torrentUrl}, 'https://ncore.pro/torrents.php?action=download&id=3119161&key=PASSKEY');

Irssi::print("TRACKERDEFS:FILES:$expected_count");
Irssi::print("TRACKERDEFS:PARSED:$expected_count");
Irssi::print("TRACKERDEFS:UNIQUE_TYPES:$expected_count");
Irssi::print("TRACKERDEFS:RELOADED:$expected_count");
Irssi::print('TRACKERDEFS:PTP_ANNOUNCE_CONFIRMED');
Irssi::print('TRACKERDEFS:NCORE_ANNOUNCE_CONFIRMED');
Irssi::print('TRACKERDEFS:VALIDATION_CONFIRMED');
AutodlIrssi::Irssi::irssi_timeout_add_once(500, sub {
	Irssi::print('TRACKERDEFS:SETTLE_COMPLETE');
	AutodlIrssi::Irssi::irssi_command('quit');
}, undef);

1;
