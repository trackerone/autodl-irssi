use 5.008;
use strict;
use warnings;

use Irssi;
use AutodlIrssi::Scgi;
use AutodlIrssi::XmlRpcSimpleCall;
use AutodlIrssi::RtorrentCommands;

our $VERSION = '1.0';
our %IRSSI = (
	authors => 'autodl-irssi test harness',
	name => 'scgi-xmlrpc-driver',
	description => 'Offline SCGI/XML-RPC/rTorrent characterization driver',
	license => 'MPL-1.1',
);

my $port = $ENV{AUTODL_SCGI_PORT};
die "AUTODL_SCGI_PORT is not a valid port\n"
	unless defined $port && $port =~ /^\d+$/ && $port > 0 && $port < 65536;
my $socket_path = $ENV{AUTODL_SCGI_SOCKET};
die "AUTODL_SCGI_SOCKET is missing\n"
	unless defined $socket_path && $socket_path ne '';

my $commands = AutodlIrssi::RtorrentCommands->new()
	->func('d.directory.set', '/downloads/TV "HD"')
	->func('d.custom.set', 'label', 'A&B')
	->func('d.tied_to_file.set')
	->get();
my $torrent_path = '/tmp/Fixture & <torrent>.torrent';
my $callback_count = 0;
my $active_call;

sub finish {
	AutodlIrssi::Irssi::irssi_timeout_add_once(500, sub {
		Irssi::print('SCGIXMLRPC:SETTLE_COMPLETE');
		AutodlIrssi::Irssi::irssi_command('quit');
	}, undef);
}

sub fail {
	my $message = shift;
	Irssi::print("SCGIXMLRPC:FAIL:$message");
	finish();
}

sub build_call {
	my $address = shift;
	my $scgi = AutodlIrssi::Scgi->new($address, {REMOTE_ADDR => '127.0.0.1'});
	my $xmlrpc = AutodlIrssi::XmlRpcSimpleCall->new($scgi);
	$xmlrpc->method('load.start');
	$xmlrpc->string($torrent_path);
	$xmlrpc->string($commands);
	$xmlrpc->methodEnd();
	return $xmlrpc;
}

sub start_unix_call {
	$active_call = build_call($socket_path);
	$active_call->send(sub {
		my ($error, $value) = @_;
		$callback_count++;
		$error = '' unless defined $error;
		$value = '' unless defined $value;
		Irssi::print("SCGIXMLRPC:UNIX_CALLBACK:$callback_count:$error:$value");
		return fail("unexpected callback count $callback_count") unless $callback_count == 2;
		return fail("unexpected Unix value '$value'") unless $value eq '';
		return fail("unexpected Unix error '$error'")
			unless $error eq 'XML-RPC call failed (17): fixture fault';
		finish();
	});
}

Irssi::print('SCGIXMLRPC:DRIVER_STARTED');
Irssi::timeout_add_once(250, sub { Irssi::print('SCGIXMLRPC:IRSSI_RESPONSIVE') }, undef);
$active_call = build_call("127.0.0.1:$port");
$active_call->send(sub {
	my ($error, $value) = @_;
	$callback_count++;
	$error = '' unless defined $error;
	$value = '' unless defined $value;
	Irssi::print("SCGIXMLRPC:TCP_CALLBACK:$callback_count:$error:$value");
	return fail("unexpected callback count $callback_count") unless $callback_count == 1;
	return fail("unexpected TCP error '$error'") unless $error eq '';
	return fail("unexpected TCP value '$value'") unless $value eq 'tcp-ok';
	start_unix_call();
});

1;
