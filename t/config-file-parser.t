use 5.038;
use strict;
use warnings;
use Test::More;
use File::Spec;
use lib '.';

use AutodlIrssi::ConfigFileParser;
use AutodlIrssi::AutodlConfigFileParser;

ok !exists $INC{'Irssi.pm'}, 'configuration parsers load without Irssi';
ok !exists $INC{'AutodlIrssi/Globals.pm'}, 'configuration parsers load without Globals';

my $validPath = File::Spec->catfile(qw(t fixtures config valid.cfg));
my @reported;
my $parser = AutodlIrssi::AutodlConfigFileParser->new(undef, sub {
	push @reported, shift;
});
$parser->parse($validPath);

is_deeply $parser->getDiagnostics(), [], 'valid fixture has no diagnostics';
is_deeply \@reported, [], 'valid fixture invokes no diagnostic handler';

my $options = $parser->getOptions();
is $options->{updateCheck}, 'disabled', 'update policy is parsed';
is $options->{uploadType}, 'test', 'upload type is parsed';
is $options->{maxDownloadRetryTimeSeconds}, 42, 'integer option is converted';
is $options->{level}, 4, 'bounded integer option is converted';
is $options->{saveDownloadHistory}, 0, 'boolean option is converted';

my $filters = $parser->getFilters();
is scalar @$filters, 1, 'one filter is parsed';
is $filters->[0]{name}, 'Current TV', 'filter name is preserved';
is $filters->[0]{matchReleases}, 'Example.Show.*', 'release matcher is preserved';
is $filters->[0]{minSize}, '750MB', 'minimum size is preserved';
is $filters->[0]{maxSize}, '4GB', 'maximum size is preserved';
is $filters->[0]{smartEpisode}, 1, 'filter boolean is converted';
is $filters->[0]{maxDownloads}, 2, 'filter integer is converted';
is $filters->[0]{maxDownloadsPer}, 'day', 'filter interval is preserved';

my $servers = $parser->getServers();
ok exists $servers->{'irc.example.org'}, 'server names are canonicalized';
is $servers->{'irc.example.org'}{nick}, 'autodl', 'server option is parsed';
ok exists $servers->{'irc.example.org'}{channels}{'#announce'}, 'channel is attached to its canonical server';
is $servers->{'irc.example.org'}{channels}{'#announce'}{password}, 'secret', 'channel option is parsed';

my $invalidPath = File::Spec->catfile(qw(t fixtures config invalid.cfg));
@reported = ();
$parser = AutodlIrssi::AutodlConfigFileParser->new(undef, sub {
	push @reported, shift;
});
$parser->parse($invalidPath);

my $diagnostics = $parser->getDiagnostics();
is_deeply \@reported, $diagnostics, 'diagnostic handler receives each collected diagnostic';
is scalar @$diagnostics, 9, 'invalid fixture reports every characterized error';

my @expected = (
	[1, 'invalid line: orphan = value'],
	[3, "OPTIONS: Unknown option 'unknown-option'"],
	[4, "Invalid upload-type 'spaceship'"],
	[5, 'upload-command set to bare wildcard. This is unnecessary and unsupported by some options.'],
	[7, 'min-size set to bare wildcard. This is unnecessary and unsupported by some options.'],
	[8, "Invalid upload-type 'bogus'"],
	[9, "FILTER: Unknown option 'made-up'"],
	[10, 'Invalid or missing channel name'],
	[12, "Unknown header 'mystery'"],
);

for my $expected (@expected) {
	my ($line, $message) = @$expected;
	my $full = "$invalidPath: line $line: $message";
	ok scalar(grep { $_ eq $full } @$diagnostics), "diagnostic records line $line";
}

done_testing;
