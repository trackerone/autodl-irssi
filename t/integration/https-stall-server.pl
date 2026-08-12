#!/usr/bin/perl
use 5.008;
use strict;
use warnings;

use IO::Socket::SSL;
use Time::HiRes qw(sleep time);

my ($ready_file, $event_log, $cert_file, $key_file, $stall_ms) = @ARGV;
die "usage: $0 READY_FILE EVENT_LOG CERT_FILE KEY_FILE STALL_MS\n"
	unless defined $stall_ms && $stall_ms =~ /^\d+$/ && $stall_ms >= 100;

my $listener = IO::Socket::SSL->new(
	LocalAddr => '127.0.0.1',
	LocalPort => 0,
	Proto => 'tcp',
	Listen => 5,
	ReuseAddr => 1,
	SSL_cert_file => $cert_file,
	SSL_key_file => $key_file,
) or die "could not create loopback TLS listener: " . IO::Socket::SSL::errstr() . "\n";

open my $ready, '>', $ready_file or die "could not open readiness FIFO: $!\n";
print {$ready} $listener->sockport(), "\n" or die "could not report port: $!\n";
close $ready or die "could not close readiness FIFO: $!\n";

open my $log, '>', $event_log or die "could not open event log: $!\n";
$log->autoflush(1);

$SIG{ALRM} = sub { die "TLS fixture exceeded its 20 second runtime\n" };
alarm 20;

my $client = $listener->accept()
	or die "TLS accept failed: " . IO::Socket::SSL::errstr() . "\n";
$client->autoflush(1);
print {$log} "TLS_HANDSHAKE_COMPLETE ", time(), "\n";

my $request = '';
while ($request !~ /\r\n\r\n\z/) {
	my $read = $client->sysread(my $chunk, 4096);
	die "TLS request read failed: " . IO::Socket::SSL::errstr() . "\n"
		unless defined $read;
	die "TLS request ended before its headers\n" if $read == 0;
	$request .= $chunk;
	die "TLS request headers exceeded 16384 bytes\n" if length($request) > 16384;
}

my ($request_line) = split /\r\n/, $request;
die "unexpected request line: $request_line\n"
	unless $request_line eq 'GET /issue-190.torrent HTTP/1.1';
die "request did not ask the server to close the connection\n"
	unless $request =~ /\r\nConnection: close\r\n/i;
print {$log} "REQUEST_RECEIVED $request_line\n";
print {$log} "STALL_BEGIN $stall_ms\n";

sleep($stall_ms / 1000);

print {$log} "STALL_END\n";
my $response = "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\nTEST";
while (length $response) {
	my $written = $client->syswrite($response);
	die "TLS response write failed: " . IO::Socket::SSL::errstr() . "\n"
		unless defined $written && $written > 0;
	substr($response, 0, $written, '');
}
print {$log} "RESPONSE_SENT HTTP/1.1 200 OK\n";

close $client or die "could not close TLS client: $!\n";
close $listener or die "could not close TLS listener: $!\n";
alarm 0;
close $log or die "could not close event log: $!\n";
exit 0;
