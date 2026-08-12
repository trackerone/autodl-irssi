#!/usr/bin/perl
use 5.008;
use strict;
use warnings;

use IO::Socket::INET;
use POSIX qw(_exit);

my ($ready_file, $request_log, $maximum) = @ARGV;
die "usage: $0 READY_FILE REQUEST_LOG MAX_REQUESTS\n"
	unless defined $maximum && $maximum =~ /^\d+$/ && $maximum > 0;

my $listener = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1',
	LocalPort => 0,
	Proto => 'tcp',
	Listen => 5,
	ReuseAddr => 1,
) or die "could not create loopback HTTP listener: $!\n";

open my $ready, '>', $ready_file or die "could not open readiness file: $!\n";
print {$ready} $listener->sockport(), "\n" or die "could not report port: $!\n";
close $ready or die "could not close readiness file: $!\n";

open my $log, '>', $request_log or die "could not open request log: $!\n";
$log->autoflush(1);

$SIG{ALRM} = sub { die "HTTP fixture exceeded its 20 second runtime\n" };
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
		unless $request_line eq 'GET /issue-210.torrent HTTP/1.1';
	die "request $number did not ask the server to close the connection\n"
		unless $request =~ /\r\nConnection: close\r\n/i;

	(my $escaped = $request) =~ s/\r/\\r/g;
	$escaped =~ s/\n/\\n/g;
	print {$log} "REQUEST $number $escaped\n";
	print {$client} "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
		or die "could not write response $number: $!\n";
	close $client or die "could not close request $number: $!\n";
	print {$log} "RESPONSE $number HTTP/1.1 401 Unauthorized\n";
}

alarm 0;
close $listener or die "could not close listener: $!\n";
close $log or die "could not close request log: $!\n";
exit 0;
