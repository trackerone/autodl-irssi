use 5.008;
use strict;
use warnings;

use Irssi;
use AutodlIrssi::HttpRequest;

our $VERSION = '1.0';
our %IRSSI = (
	authors => 'autodl-irssi test harness',
	name => 'http-incomplete-header-driver',
	description => 'Offline issue 191 incomplete HTTP header characterization driver',
	license => 'MPL-1.1',
);

my $port = $ENV{AUTODL_HTTP_INCOMPLETE_HEADER_PORT};
die "AUTODL_HTTP_INCOMPLETE_HEADER_PORT is not a valid port\n"
	unless defined $port && $port =~ /^\d+$/ && $port > 0 && $port < 65536;

$AutodlIrssi::g->{options}{maxDownloadRetryTimeSeconds} = 3;
our $request = AutodlIrssi::HttpRequest->new();
our $final_count = 0;

Irssi::print('HTTPHEADER:DRIVER_STARTED');
AutodlIrssi::Irssi::irssi_timeout_add_once(500, sub {
	Irssi::print('HTTPHEADER:IRSSI_RESPONSIVE');
}, undef);

$request->sendRequest(
	'GET',
	'',
	"http://127.0.0.1:$port/issue-191-settings",
	{},
	sub {
		my ($error_message) = @_;
		$final_count++;
		Irssi::print("HTTPHEADER:FINAL_CALLBACK:$final_count:$error_message");
		AutodlIrssi::Irssi::irssi_timeout_add_once(1000, sub {
			Irssi::print('HTTPHEADER:SETTLE_COMPLETE');
			AutodlIrssi::Irssi::irssi_command('quit');
		}, undef);
	},
);

1;
