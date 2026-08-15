use 5.008;
use strict;
use warnings;

use Archive::Zip qw/ :ERROR_CODES /;
use Digest::SHA qw/ sha256_hex /;
use File::Copy qw/ copy /;
use File::Spec;
use File::Temp qw/ tempfile tempdir /;
use Irssi;
use AutodlIrssi::Dirs;
use AutodlIrssi::InternetUtils qw/ decodeJson encodeJson /;
use AutodlIrssi::Updater;

our $VERSION = '1.0';
our %IRSSI = (
	authors => 'autodl-irssi test harness',
	name => 'tracker-update-install-driver',
	description => 'Offline issue 198 tracker installation characterization driver',
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

sub build_zip {
	my $members = shift;
	my $zip = Archive::Zip->new();
	for my $member (@$members) {
		$zip->addString($member->[1], $member->[0]);
	}

	my ($fh, $filename) = tempfile('tracker-update-XXXXXX', TMPDIR => 1, UNLINK => 1);
	close $fh or die "Could not close temporary ZIP file: $!\n";
	$zip->writeToFileNamed($filename) == AZ_OK
		or die "Could not write temporary tracker ZIP file\n";
	return slurp_file($filename);
}

{
	package TrackerUpdateFixtureRequest;

	sub new {
		my ($class, $responses, $requests) = @_;
		return bless { responses => $responses, requests => $requests }, $class;
	}

	sub sendRequest {
		my ($self, $method, $body, $url, $headers, $handler) = @_;
		$self->{url} = $url;
		push @{$self->{requests}}, $url;
		die "No fixture response for '$url'\n" unless exists $self->{responses}{$url};
		$self->{response_data} = $self->{responses}{$url};
		$handler->('');
	}

	sub getResponseStatusCode { return 200; }
	sub getResponseStatusText { return 'HTTP/1.1 200 OK'; }
	sub getResponseData { return shift->{response_data}; }
	sub cancel { }
}

{
	package TrackerUpdateFixtureUpdater;
	use parent 'AutodlIrssi::Updater';

	sub new {
		my ($class, $responses) = @_;
		my $self = $class->SUPER::new();
		$self->{fixture_responses} = $responses;
		$self->{fixture_requests} = [];
		return $self;
	}

	sub _createHttpRequest {
		my $self = shift;
		$self->{request} = TrackerUpdateFixtureRequest->new(
			$self->{fixture_responses}, $self->{fixture_requests});
	}

	sub _installStagedTrackerFile {
		my ($self, @args) = @_;
		if (defined $self->{fail_install_after}) {
			die "Injected tracker installation failure\n" if $self->{fail_install_after}-- == 0;
		}
		return $self->SUPER::_installStagedTrackerFile(@args);
	}
}

my $fixture_dir = $ENV{AUTODL_TRACKER_UPDATE_FIXTURE_DIR};
die "AUTODL_TRACKER_UPDATE_FIXTURE_DIR is required\n"
	unless defined $fixture_dir && -d $fixture_dir;
my $release_dir = $ENV{AUTODL_TRACKER_RELEASE_DIR};
die "AUTODL_TRACKER_RELEASE_DIR is required\n"
	unless defined $release_dir && -d $release_dir;
my $source_dir = $ENV{AUTODL_TRACKER_SOURCE_DIR};
die "AUTODL_TRACKER_SOURCE_DIR is required\n"
	unless defined $source_dir && -d $source_dir;

my $updated_data = slurp_file(File::Spec->catfile($fixture_dir, 'updated.tracker'));
my $added_data = slurp_file(File::Spec->catfile($fixture_dir, 'added.tracker'));
my $release_data = decodeJson(slurp_file(
	File::Spec->catfile($fixture_dir, 'trackerone-releases.json')));
my $version = slurp_file(File::Spec->catfile($source_dir, 'VERSION'));
$version =~ s/\s+$//;
die "Invalid tracker fixture version '$version'\n" unless $version =~ /^\d+(?:\.\d+)*$/;
my $asset_name = "autodl-trackers-v$version.zip";
my $asset_url = "https://github.com/trackerone/autodl-irssi/releases/download/trackers-v$version/$asset_name";
my $checksum_url = "$asset_url.sha256";
for my $release (@$release_data) {
	next unless $release->{tag_name} eq 'trackers-v291.0' && !$release->{prerelease};
	$release->{tag_name} = "trackers-v$version";
	$release->{assets} = [
		{ name => $asset_name, browser_download_url => $asset_url },
		{ name => "$asset_name.sha256", browser_download_url => $checksum_url },
	];
}
my $release_json = encodeJson($release_data);
my $zip_data = slurp_file(File::Spec->catfile($release_dir, $asset_name));
my $checksum_data = slurp_file(File::Spec->catfile($release_dir, "$asset_name.sha256"));
my %responses = (
	AutodlIrssi::Updater::TRACKERS_UPDATE_URL() => $release_json,
	$checksum_url => $checksum_data,
	$asset_url => $zip_data,
);
my $tracker_dir = getTrackerFilesDir();
my $callback_count = 0;
my $callback_error;
my $check_callback_count = 0;
my $check_callback_error;

Irssi::print('TRACKERUPDATE:DRIVER_STARTED');
my $updater = TrackerUpdateFixtureUpdater->new(\%responses);
die "Unexpected trackers release API URL\n"
	unless AutodlIrssi::Updater::TRACKERS_UPDATE_URL()
		eq 'https://api.github.com/repos/trackerone/autodl-irssi/releases?per_page=100';

my @missing_asset_data = map { { %$_ } } @$release_data;
for my $release (@missing_asset_data) {
	$release->{assets} = [] if $release->{tag_name} eq "trackers-v$version";
}
eval { $updater->_parseTrackersUpdate(\@missing_asset_data); };
die "Missing release asset was not rejected\n" unless $@;
die "Unexpected missing release asset error: $@"
	unless $@ eq "Could not find trackers release asset '$asset_name'\n";

my @missing_checksum_data = map { { %$_ } } @$release_data;
for my $release (@missing_checksum_data) {
	next unless $release->{tag_name} eq "trackers-v$version";
	$release->{assets} = [grep { $_->{name} !~ /\.sha256$/ } @{$release->{assets}}];
}
eval { $updater->_parseTrackersUpdate(\@missing_checksum_data); };
die "Missing release checksum was not rejected\n" unless $@;
die "Unexpected missing release checksum error: $@"
	unless $@ eq "Could not find trackers release checksum '$asset_name.sha256'\n";

$updater->checkTrackersUpdate(sub {
	($check_callback_error) = @_;
	$check_callback_count++;
});
die "Update check callback count was $check_callback_count, expected 1\n"
	unless $check_callback_count == 1;
die "Update check callback reported '$check_callback_error'\n" if $check_callback_error;
die "Unexpected trackers version\n" unless $updater->getTrackersVersion() eq $version;
die "Updated trackers version was not detected\n" unless $updater->hasTrackersUpdate('284');
die "Unexpected trackers release asset URL\n"
	unless $updater->{trackers}{url}
		eq $asset_url;
die "Unexpected trackers release checksum URL\n"
	unless $updater->{trackers}{checksumUrl} eq $checksum_url;
Irssi::print('TRACKERUPDATE:SOURCE:trackerone/autodl-irssi');
Irssi::print("TRACKERUPDATE:VERSION:$version");
Irssi::print("TRACKERUPDATE:ASSET:$asset_name");
Irssi::print("TRACKERUPDATE:CHECKSUM_ASSET:$asset_name.sha256");
Irssi::print('TRACKERUPDATE:MISSING_ASSET_REJECTED');
Irssi::print('TRACKERUPDATE:MISSING_CHECKSUM_REJECTED');

$responses{$asset_url} = $zip_data . 'tampered';
$updater->updateTrackers($tracker_dir, sub {
	($callback_error) = @_;
	$callback_count++;
});
die "Checksum failure callback count was $callback_count, expected 1\n" unless $callback_count == 1;
die "Tampered tracker archive was not rejected\n"
	unless $callback_error && $callback_error =~ /Trackers checksum mismatch/;
my @unchanged_files = sort map { (File::Spec->splitpath($_))[2] }
	$AutodlIrssi::g->{trackerManager}->getTrackerFiles($tracker_dir);
die "Checksum failure changed installed files to '@unchanged_files'\n"
	unless "@unchanged_files" eq 'current.tracker obsolete.tracker';
Irssi::print('TRACKERUPDATE:CHECKSUM_MISMATCH_REJECTED');

$responses{$asset_url} = $zip_data;
$callback_count = 0;
$callback_error = undef;
$updater->updateTrackers($tracker_dir, sub {
	($callback_error) = @_;
	$callback_count++;
	Irssi::print("TRACKERUPDATE:FINAL_CALLBACK:$callback_count:$callback_error");
});
my @expected_requests = (
	AutodlIrssi::Updater::TRACKERS_UPDATE_URL(),
	$checksum_url, $asset_url,
	$checksum_url, $asset_url,
);
die "Updater request sequence was '@{$updater->{fixture_requests}}'\n"
	unless "@{$updater->{fixture_requests}}" eq "@expected_requests";

my @tracker_files = sort map { (File::Spec->splitpath($_))[2] }
	$AutodlIrssi::g->{trackerManager}->getTrackerFiles($tracker_dir);
my $obsolete_file = File::Spec->catfile($tracker_dir, 'obsolete.tracker');
opendir my $source_dh, $source_dir or die "Could not open '$source_dir': $!\n";
my @expected_files = sort grep { /\.tracker$/ && -f File::Spec->catfile($source_dir, $_) }
	readdir $source_dh;
closedir $source_dh;

die "Updater callback count was $callback_count, expected 1\n" unless $callback_count == 1;
die "Updater callback reported '$callback_error'\n" if $callback_error;
die "Installed tracker file list was '@tracker_files'\n"
	unless "@tracker_files" eq "@expected_files";
die "Obsolete tracker file was not removed\n" if -e $obsolete_file;
for my $file (@expected_files) {
	die "Installed tracker '$file' differs from release source\n"
		unless slurp_file(File::Spec->catfile($tracker_dir, $file))
			eq slurp_file(File::Spec->catfile($source_dir, $file));
}

$AutodlIrssi::g->{trackerManager}->reloadTrackerFiles($tracker_dir);
my @loaded_types = sort keys %{$AutodlIrssi::g->{trackerManager}{announceParsers}};
die "Reloaded " . scalar(@loaded_types) . " tracker types, expected " . scalar(@expected_files) . "\n"
	unless @loaded_types == @expected_files;

my $rollback_dir = tempdir('autodl-tracker-rollback-XXXXXX', DIR => $ENV{HOME}, CLEANUP => 1);
my $original_current = slurp_file(File::Spec->catfile($fixture_dir, '..', 'irssi', 'minimal.tracker'));
my $original_obsolete = slurp_file(File::Spec->catfile($fixture_dir, 'obsolete.tracker'));
my $rollback_current = File::Spec->catfile($rollback_dir, 'current.tracker');
my $rollback_obsolete = File::Spec->catfile($rollback_dir, 'obsolete.tracker');
copy(File::Spec->catfile($fixture_dir, '..', 'irssi', 'minimal.tracker'), $rollback_current)
	or die "Could not prepare rollback current tracker: $!\n";
copy(File::Spec->catfile($fixture_dir, 'obsolete.tracker'), $rollback_obsolete)
	or die "Could not prepare rollback obsolete tracker: $!\n";
my $small_zip = build_zip([
	['current.tracker', $updated_data],
	['added.tracker', $added_data],
]);
my $failing_updater = TrackerUpdateFixtureUpdater->new({});
$failing_updater->{fail_install_after} = 1;
eval { $failing_updater->_installTrackerZip($small_zip, $rollback_dir); };
die "Injected tracker installation failure was not reported\n"
	unless $@ =~ /Injected tracker installation failure/;
my @rollback_files = sort map { (File::Spec->splitpath($_))[2] }
	$AutodlIrssi::g->{trackerManager}->getTrackerFiles($rollback_dir);
die "Rollback restored files '@rollback_files'\n"
	unless "@rollback_files" eq 'current.tracker obsolete.tracker';
die "Rollback did not restore current tracker\n"
	unless slurp_file($rollback_current) eq $original_current;
die "Rollback did not restore obsolete tracker\n"
	unless slurp_file($rollback_obsolete) eq $original_obsolete;
Irssi::print('TRACKERUPDATE:ROLLBACK_CONFIRMED');

my $escape_file = File::Spec->catfile($ENV{HOME}, 'escape.tracker');
my $traversal_zip = build_zip([['../escape.tracker', $updated_data]]);
eval { $failing_updater->_installTrackerZip($traversal_zip, $rollback_dir); };
die "Archive traversal member was not rejected\n" unless $@ =~ /Invalid tracker archive member/;
die "Archive traversal wrote outside its destination\n" if -e $escape_file;
die "Archive validation changed the existing installation\n"
	unless slurp_file($rollback_current) eq $original_current
		&& slurp_file($rollback_obsolete) eq $original_obsolete;
Irssi::print('TRACKERUPDATE:ARCHIVE_VALIDATION_REJECTED');
Irssi::print('TRACKERUPDATE:REQUEST_SEQUENCE_CONFIRMED');

Irssi::print('TRACKERUPDATE:FILES:' . scalar(@tracker_files));
Irssi::print('TRACKERUPDATE:LOADED_TYPES:' . scalar(@loaded_types));
Irssi::print('TRACKERUPDATE:INSTALL_CONFIRMED');
AutodlIrssi::Irssi::irssi_timeout_add_once(500, sub {
	Irssi::print('TRACKERUPDATE:SETTLE_COMPLETE');
	AutodlIrssi::Irssi::irssi_command('quit');
}, undef);

1;
