use 5.008;
use strict;
use warnings;

use Archive::Zip qw/ :ERROR_CODES /;
use File::Spec;
use File::Temp qw/ tempfile /;
use Irssi;
use AutodlIrssi::Dirs;
use AutodlIrssi::InternetUtils qw/ decodeJson /;
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

sub build_release_zip {
	my ($updated_data, $added_data) = @_;
	my $zip = Archive::Zip->new();
	$zip->addString($updated_data, 'current.tracker');
	$zip->addString($added_data, 'added.tracker');

	my ($fh, $filename) = tempfile('tracker-update-XXXXXX', TMPDIR => 1, UNLINK => 1);
	close $fh or die "Could not close temporary ZIP file: $!\n";
	$zip->writeToFileNamed($filename) == AZ_OK
		or die "Could not write temporary tracker ZIP file\n";
	return slurp_file($filename);
}

{
	package TrackerUpdateFixtureRequest;

	sub new {
		my ($class, $response_data) = @_;
		return bless { response_data => $response_data }, $class;
	}

	sub sendRequest {
		my ($self, $method, $body, $url, $headers, $handler) = @_;
		$self->{url} = $url;
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
		my ($class, $response_data) = @_;
		my $self = $class->SUPER::new();
		$self->{fixture_response_data} = $response_data;
		return $self;
	}

	sub _createHttpRequest {
		my $self = shift;
		$self->{request} = TrackerUpdateFixtureRequest->new($self->{fixture_response_data});
	}
}

my $fixture_dir = $ENV{AUTODL_TRACKER_UPDATE_FIXTURE_DIR};
die "AUTODL_TRACKER_UPDATE_FIXTURE_DIR is required\n"
	unless defined $fixture_dir && -d $fixture_dir;

my $updated_data = slurp_file(File::Spec->catfile($fixture_dir, 'updated.tracker'));
my $added_data = slurp_file(File::Spec->catfile($fixture_dir, 'added.tracker'));
my $release_json = slurp_file(File::Spec->catfile($fixture_dir, 'trackerone-releases.json'));
my $release_data = decodeJson($release_json);
my $zip_data = build_release_zip($updated_data, $added_data);
my $tracker_dir = getTrackerFilesDir();
my $callback_count = 0;
my $callback_error;
my $check_callback_count = 0;
my $check_callback_error;

Irssi::print('TRACKERUPDATE:DRIVER_STARTED');
my $updater = TrackerUpdateFixtureUpdater->new($release_json);
die "Unexpected trackers release API URL\n"
	unless AutodlIrssi::Updater::TRACKERS_UPDATE_URL()
		eq 'https://api.github.com/repos/trackerone/autodl-irssi/releases?per_page=100';

my @missing_asset_data = map { { %$_ } } @$release_data;
for my $release (@missing_asset_data) {
	$release->{assets} = [] if $release->{tag_name} eq 'trackers-v291.0';
}
eval { $updater->_parseTrackersUpdate(\@missing_asset_data); };
die "Missing release asset was not rejected\n" unless $@;
die "Unexpected missing release asset error: $@"
	unless $@ eq "Could not find trackers release asset 'autodl-trackers-v291.0.zip'\n";

$updater->checkTrackersUpdate(sub {
	($check_callback_error) = @_;
	$check_callback_count++;
});
die "Update check callback count was $check_callback_count, expected 1\n"
	unless $check_callback_count == 1;
die "Update check callback reported '$check_callback_error'\n" if $check_callback_error;
die "Unexpected trackers version\n" unless $updater->getTrackersVersion() eq '291.0';
die "Updated trackers version was not detected\n" unless $updater->hasTrackersUpdate('284');
die "Unexpected trackers release asset URL\n"
	unless $updater->{trackers}{url}
		eq 'https://github.com/trackerone/autodl-irssi/releases/download/trackers-v291.0/autodl-trackers-v291.0.zip';
Irssi::print('TRACKERUPDATE:SOURCE:trackerone/autodl-irssi');
Irssi::print('TRACKERUPDATE:VERSION:291.0');
Irssi::print('TRACKERUPDATE:ASSET:autodl-trackers-v291.0.zip');
Irssi::print('TRACKERUPDATE:MISSING_ASSET_REJECTED');

$updater->{fixture_response_data} = $zip_data;
$updater->updateTrackers($tracker_dir, sub {
	($callback_error) = @_;
	$callback_count++;
	Irssi::print("TRACKERUPDATE:FINAL_CALLBACK:$callback_count:$callback_error");
});

my @tracker_files = sort map { (File::Spec->splitpath($_))[2] }
	$AutodlIrssi::g->{trackerManager}->getTrackerFiles($tracker_dir);
my $current_file = File::Spec->catfile($tracker_dir, 'current.tracker');
my $added_file = File::Spec->catfile($tracker_dir, 'added.tracker');
my $obsolete_file = File::Spec->catfile($tracker_dir, 'obsolete.tracker');

die "Updater callback count was $callback_count, expected 1\n" unless $callback_count == 1;
die "Updater callback reported '$callback_error'\n" if $callback_error;
die "Installed tracker file list was '@tracker_files'\n"
	unless "@tracker_files" eq 'added.tracker current.tracker';
die "Current tracker contents were not replaced\n"
	unless slurp_file($current_file) eq $updated_data;
die "Added tracker contents do not match the release archive\n"
	unless slurp_file($added_file) eq $added_data;
die "Obsolete tracker file was not removed\n" if -e $obsolete_file;

$AutodlIrssi::g->{trackerManager}->reloadTrackerFiles($tracker_dir);
my @loaded_types = sort keys %{$AutodlIrssi::g->{trackerManager}{announceParsers}};
die "Reloaded tracker types were '@loaded_types'\n"
	unless "@loaded_types" eq 'added-fixture updated-fixture';

Irssi::print('TRACKERUPDATE:FILES:added.tracker,current.tracker');
Irssi::print('TRACKERUPDATE:LOADED_TYPES:added-fixture,updated-fixture');
Irssi::print('TRACKERUPDATE:INSTALL_CONFIRMED');
AutodlIrssi::Irssi::irssi_timeout_add_once(500, sub {
	Irssi::print('TRACKERUPDATE:SETTLE_COMPLETE');
	AutodlIrssi::Irssi::irssi_command('quit');
}, undef);

1;
