#!/usr/bin/perl
use 5.008;
use strict;
use warnings;

use IO::Socket::INET;
use IO::Socket::UNIX;
use Socket qw(SOCK_STREAM);

my ($transport, $ready_file, $endpoint, $request_log, $response_kind) = @ARGV;
die "usage: $0 TRANSPORT READY_FILE ENDPOINT REQUEST_LOG RESPONSE_KIND\n"
	unless defined $response_kind;
die "transport must be tcp or unix\n"
	unless $transport eq 'tcp' || $transport eq 'unix';
die "response kind must be success or fault\n"
	unless $response_kind eq 'success' || $response_kind eq 'fault';

# Open the synchronization channel before creating the listener. If listener
# setup fails, the waiting shell sees EOF instead of blocking on an unopened
# FIFO until the outer CI timeout.
open my $ready, '>', $ready_file or die "could not open readiness file: $!\n";

my $listener;
my $reported_endpoint;
if ($transport eq 'tcp') {
	$listener = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => 0,
		Proto => 'tcp',
		Listen => 1,
		ReuseAddr => 1,
	) or die "could not create loopback SCGI listener: $!\n";
	$reported_endpoint = $listener->sockport();
}
else {
	die "Unix socket endpoint is missing\n" unless defined $endpoint && $endpoint ne '';
	unlink $endpoint if -e $endpoint;
	$listener = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Local => $endpoint,
		Listen => 1,
	) or die "could not create Unix SCGI listener '$endpoint': $!\n";
	$reported_endpoint = $endpoint;
}
print {$ready} $reported_endpoint, "\n" or die "could not report endpoint: $!\n";
close $ready or die "could not close readiness file: $!\n";

open my $log, '>', $request_log or die "could not open request log: $!\n";
$log->autoflush(1);

$SIG{ALRM} = sub { die "SCGI fixture exceeded its 20 second runtime\n" };
alarm 20;

my $client = $listener->accept() or die "accept failed: $!\n";
$client->autoflush(1);

my $buffer = '';
while ($buffer !~ /:/) {
	my $read = sysread($client, my $chunk, 4096);
	die "failed to read SCGI length: $!\n" unless defined $read;
	die "connection ended before SCGI length\n" if $read == 0;
	$buffer .= $chunk;
	die "SCGI length prefix exceeded 32 bytes\n" if length($buffer) > 32 && $buffer !~ /:/;
}

my ($header_length_string, $remainder) = split /:/, $buffer, 2;
die "invalid SCGI header length '$header_length_string'\n"
	unless $header_length_string =~ /^\d+$/;
my $header_length = 0 + $header_length_string;
die "SCGI header length is out of bounds\n"
	if $header_length <= 0 || $header_length > 65536;
$buffer = $remainder;

while (length($buffer) < $header_length + 1) {
	my $read = sysread($client, my $chunk, 4096);
	die "failed to read SCGI headers: $!\n" unless defined $read;
	die "connection ended before SCGI headers\n" if $read == 0;
	$buffer .= $chunk;
}

my $header_data = substr($buffer, 0, $header_length, '');
my $comma = substr($buffer, 0, 1, '');
die "SCGI netstring is missing its comma\n" unless $comma eq ',';
my @header_parts = split /\0/, $header_data, -1;
die "SCGI header is not NUL terminated\n" unless pop(@header_parts) eq '';
die "SCGI header has an unmatched key\n" if @header_parts % 2;

my @headers;
while (@header_parts) {
	push @headers, [shift @header_parts, shift @header_parts];
}
die "CONTENT_LENGTH is not the first SCGI header\n"
	unless @headers && $headers[0][0] eq 'CONTENT_LENGTH';
my %headers = map { $_->[0] => $_->[1] } @headers;
die "invalid CONTENT_LENGTH\n"
	unless defined $headers{CONTENT_LENGTH} && $headers{CONTENT_LENGTH} =~ /^\d+$/;
die "missing required SCGI header\n"
	unless defined $headers{SCGI} && $headers{SCGI} eq '1';
die "unexpected REMOTE_ADDR\n"
	unless defined $headers{REMOTE_ADDR} && $headers{REMOTE_ADDR} eq '127.0.0.1';

my $content_length = 0 + $headers{CONTENT_LENGTH};
while (length($buffer) < $content_length) {
	my $read = sysread($client, my $chunk, 4096);
	die "failed to read XML-RPC body: $!\n" unless defined $read;
	die "connection ended before XML-RPC body\n" if $read == 0;
	$buffer .= $chunk;
}
die "SCGI request contains trailing data\n" if length($buffer) != $content_length;
my $xml = $buffer;

sub decode_xml_text {
	my $text = shift;
	$text =~ s/&lt;/</g;
	$text =~ s/&gt;/>/g;
	$text =~ s/&amp;/&/g;
	return $text;
}

my ($method) = $xml =~ m!<methodCall><methodName>([^<]*)</methodName><params>!;
die "missing XML-RPC method\n" unless defined $method;
$method = decode_xml_text($method);
die "unexpected XML-RPC method '$method'\n" unless $method eq 'load.start';
my @params = map { decode_xml_text($_) }
	($xml =~ m!<param><value><string>(.*?)</string></value></param>!g);
die "expected three XML-RPC string parameters\n" unless @params == 3;
die "rTorrent compatibility parameter is not empty\n" unless $params[0] eq '';
die "unexpected torrent path '$params[1]'\n"
	unless $params[1] eq '/tmp/Fixture & <torrent>.torrent';
my $expected_commands = 'd.directory.set="/downloads/TV \\"HD\\"";d.custom.set="label","A&B";d.tied_to_file.set=';
die "unexpected rTorrent commands '$params[2]'\n" unless $params[2] eq $expected_commands;
die "torrent path was not escaped in XML\n"
	unless $xml =~ m!Fixture &amp; &lt;torrent&gt;\.torrent!;
die "command ampersand was not escaped in XML\n" unless $xml =~ m!A&amp;B!;

print {$log} "TRANSPORT $transport\n";
print {$log} "SCGI_HEADER_LENGTH $header_length\n";
print {$log} "CONTENT_LENGTH $content_length\n";
print {$log} "METHOD $method\n";
print {$log} "PARAMETERS " . scalar(@params) . "\n";
print {$log} "REQUEST_VALIDATED\n";

# Keep the first response pending long enough to prove the packaged Irssi event
# loop remains responsive while the production socket waits for SCGI data.
select undef, undef, undef, ($transport eq 'tcp' ? 0.60 : 0.10);

my $response_xml;
if ($response_kind eq 'success') {
	$response_xml = '<?xml version="1.0"?><methodResponse><params><param><value><string>tcp-ok</string></value></param></params></methodResponse>';
}
else {
	$response_xml = '<?xml version="1.0"?><methodResponse><fault><value><struct>'
		. '<member><name>faultCode</name><value><int>17</int></value></member>'
		. '<member><name>faultString</name><value><string>fixture fault</string></value></member>'
		. '</struct></value></fault></methodResponse>';
}
my $response = "Status: 200 OK\r\nContent-Type: text/xml\r\n\r\n$response_xml";
print {$client} $response or die "could not write SCGI response: $!\n";
close $client or die "could not close SCGI connection: $!\n";
print {$log} "RESPONSE $response_kind\n";

alarm 0;
close $listener or die "could not close listener: $!\n";
close $log or die "could not close request log: $!\n";
unlink $endpoint if $transport eq 'unix' && -e $endpoint;
exit 0;
