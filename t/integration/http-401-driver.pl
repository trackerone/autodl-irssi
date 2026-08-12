use 5.008;
use strict;
use warnings;

use Irssi;
use AutodlIrssi::FilterState;
use AutodlIrssi::MatchedRelease;

our $VERSION = '1.0';
our %IRSSI = (
	authors => 'autodl-irssi test harness',
	name => 'http-401-driver',
	description => 'Offline issue 210 characterization driver',
	license => 'MPL-1.1',
);

# These two tiny collaborators replace only history persistence/duplicate
# detection and tracker announce metadata. HTTP, sockets, timers, and the
# MatchedRelease implementation remain the production implementations.
{
	package Http401HistoryStub;
	sub new { bless {}, shift }
	sub canDownload { 1 }
}
{
	package Http401AnnounceStub;
	sub new { bless {}, shift }
	sub getTrackerInfo {
		return { type => 'http-401-fixture', longName => 'HTTP 401 fixture', follow302 => 0 };
	}
	sub getUninitializedDownloadVars { return [] }
	sub readOption { return undef }
}
{
	package Http401ObservedRelease;
	use parent 'AutodlIrssi::MatchedRelease';
	our $final_count = 0;
	sub _messageFail {
		my ($self, $level, $message) = @_;
		$self->SUPER::_messageFail($level, $message);
		$final_count++;
		Irssi::print("HTTP401:FINAL_CALLBACK:$final_count:$message");
		Irssi::timeout_add_once(1000, sub {
			Irssi::print('HTTP401:SETTLE_COMPLETE');
			Irssi::command('quit');
		}, undef);
	}
}

my $port = $ENV{AUTODL_HTTP401_PORT};
die "AUTODL_HTTP401_PORT is not a valid port\n"
	unless defined $port && $port =~ /^\d+$/ && $port > 0 && $port < 65536;

$AutodlIrssi::g->{options}{maxDownloadRetryTimeSeconds} = 3;
my $release = Http401ObservedRelease->new(Http401HistoryStub->new());
my $filter_state = AutodlIrssi::FilterState->new();
my $torrent_info = {
	torrentName => 'Issue.210.Offline.Reproducer',
	canonicalizedName => 'issue.210.offline.reproducer',
	torrentUrl => "http://127.0.0.1:$port/issue-210.torrent",
	httpHeaders => {},
	filter => {
		state => $filter_state,
		downloadDupeReleases => 0,
		smartEpisode => 0,
	},
	announceParser => Http401AnnounceStub->new(),
};

Irssi::print('HTTP401:DRIVER_STARTED');
Irssi::timeout_add_once(500, sub { Irssi::print('HTTP401:IRSSI_RESPONSIVE') }, undef);
$release->start($torrent_info);

1;
