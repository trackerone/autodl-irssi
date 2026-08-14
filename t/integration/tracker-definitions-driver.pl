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

Irssi::print("TRACKERDEFS:FILES:$expected_count");
Irssi::print("TRACKERDEFS:PARSED:$expected_count");
Irssi::print("TRACKERDEFS:UNIQUE_TYPES:$expected_count");
Irssi::print("TRACKERDEFS:RELOADED:$expected_count");
Irssi::print('TRACKERDEFS:VALIDATION_CONFIRMED');
AutodlIrssi::Irssi::irssi_timeout_add_once(500, sub {
	Irssi::print('TRACKERDEFS:SETTLE_COMPLETE');
	AutodlIrssi::Irssi::irssi_command('quit');
}, undef);

1;
