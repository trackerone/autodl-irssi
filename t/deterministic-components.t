use 5.038;
use strict;
use warnings;
use Test::More;
use Time::Local qw(timegm);
use lib '.';
use AutodlIrssi::FilterState;
use AutodlIrssi::LineBuffer;
use AutodlIrssi::RtorrentCommands;

my @lines;
my $buffer = AutodlIrssi::LineBuffer->new(sub { push @lines, shift });
$buffer->addData("one\r");
$buffer->addData("\ntwo\npartial");
$buffer->flushData;
is_deeply \@lines, [qw(one two partial)], 'line buffering handles chunks, CRLF, and flush';

my $commands = AutodlIrssi::RtorrentCommands->new;
$commands->func('d.directory.set', '/media/TV "HD"')->func('d.start');
is $commands->get, 'd.directory.set="/media/TV \\"HD\\"";d.start=', 'rTorrent arguments are escaped deterministically';

my $state = AutodlIrssi::FilterState->new;
my $instant = timegm(0, 30, 12, 10, 7, 126); # 2026-08-10 12:30 UTC (Monday)
$state->initializeTime($instant);
is $state->getHourTime, timegm(0, 0, 12, 10, 7, 126), 'hour boundary is UTC';
is $state->getDayTime, timegm(0, 0, 0, 10, 7, 126), 'day boundary is UTC';
is $state->getWeekTime, timegm(0, 0, 0, 10, 7, 126), 'week starts on Monday';
$state->incrementDownloads;
is $state->getTotalDownloads, 1, 'download counters increment';

done_testing;
