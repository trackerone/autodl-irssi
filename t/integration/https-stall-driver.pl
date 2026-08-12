use 5.008;
use strict;
use warnings;

use Irssi;
use AutodlIrssi::HttpRequest;

our $VERSION = '1.0';
our %IRSSI = (
	authors => 'autodl-irssi test harness',
	name => 'https-stall-driver',
	description => 'Offline issue 190 TLS read-stall characterization driver',
	license => 'MPL-1.1',
);

{
	package HttpsStallObservedRequest;
	use parent 'AutodlIrssi::HttpRequest';

	sub _onSendComplete {
		my ($self, $error_message) = @_;
		Irssi::print('HTTPSSTALL:REQUEST_SENT') unless $error_message;
		AutodlIrssi::Irssi::irssi_timeout_add_once(500, sub {
			Irssi::print('HTTPSSTALL:IRSSI_TIMER_FIRED');
		}, undef) unless $error_message;
		$self->SUPER::_onSendComplete($error_message);
	}
}

my $port = $ENV{AUTODL_HTTPS_STALL_PORT};
die "AUTODL_HTTPS_STALL_PORT is not a valid port\n"
	unless defined $port && $port =~ /^\d+$/ && $port > 0 && $port < 65536;

our $request = HttpsStallObservedRequest->new();
our $final_count = 0;
Irssi::print('HTTPSSTALL:DRIVER_STARTED');
$request->sendRequest(
	'GET',
	'',
	"https://127.0.0.1:$port/issue-190.torrent",
	{},
	sub {
		my ($error_message) = @_;
		$final_count++;
		if ($error_message) {
			Irssi::print("HTTPSSTALL:FINAL_CALLBACK:$final_count:ERROR:$error_message");
		}
		else {
			my $status = $request->getResponseStatusText();
			my $length = length $request->getResponseData();
			Irssi::print("HTTPSSTALL:FINAL_CALLBACK:$final_count:SUCCESS:$status:$length");
		}

		AutodlIrssi::Irssi::irssi_timeout_add_once(1000, sub {
			Irssi::print('HTTPSSTALL:SETTLE_COMPLETE');
			AutodlIrssi::Irssi::irssi_command('quit');
		}, undef);
	},
);

1;
