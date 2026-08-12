#!/usr/bin/perl
use 5.008;
use strict;
use warnings;

use IO::Socket::INET;

my ($ready_file, $event_log, $maximum) = @ARGV;
die "usage: $0 READY_FILE EVENT_LOG MAX_REQUESTS\n"
	unless defined $maximum && $maximum =~ /^\d+$/ && $maximum > 0;

my $listener = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1',
	LocalPort => 0,
	Proto => 'tcp',
	Listen => 5,
	ReuseAddr => 1,
) or die "could not create loopback HTTP listener: $!\n";

open my $ready, '>', $ready_file or die "could not open readiness FIFO: $!\n";
print {$ready} $listener->sockport(), "\n" or die "could not report port: $!\n";
close $ready or die "could not close readiness FIFO: $!\n";

open my $log, '>', $event_log or die "could not open event log: $!\n";
$log->autoflush(1);

$SIG{ALRM} = sub { die "incomplete-header fixture exceeded its 20 second runtime\n" };
alarm 20;

for my $number (1 .. $maximum) {
	my $client = $listener->accept() or die "accept failed: $!\n";
	$client->autoflush(1);
	my $request = '';
	while ($request !~ /\r\n\r\n\z/) {
		my $read = sysread($client, my $chunk, 4096);
		die "read failed for request $number: $!\n" unless defined $read;
		die "request $number ended before its headers\n" if $read == 0;
		$request .= $chunk;
		die "request $number headers exceeded 16384 bytes\n" if length($request) > 16384;
	}

	my ($request_line) = split /\r\n/, $request;
	die "unexpected request line for request $number: $request_line\n"
		unless $request_line eq 'GET /issue-191-settings HTTP/1.1';
	die "request $number did not ask the server to close the connection\n"
		unless $request =~ /\r\nConnection: close\r\n/i;
	print {$log} "REQUEST $number $request_line\n";

	# Deliberately close in the middle of a header field, before CRLF CRLF.
	print {$client} "HTTP/1.1 200 OK\r\nContent-Len"
		or die "could not write partial response $number: $!\n";
	close $client or die "could not close request $number: $!\n";
	print {$log} "PARTIAL_RESPONSE $number HTTP/1.1 200 OK Content-Len\n";
}

alarm 0;
close $listener or die "could not close listener: $!\n";
close $log or die "could not close event log: $!\n";
exit 0;
