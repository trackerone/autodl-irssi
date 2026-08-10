use 5.038;
use strict;
use warnings;
use Test::More;
use lib '.';
use AutodlIrssi::TextUtils;

is convertByteSizeString('1.5 MiB'), 1572864, 'binary byte size is parsed';
is convertByteSizeString('1,024 KB'), 1048576, 'grouped byte size is parsed';
ok !defined convertByteSizeString('12 parsecs'), 'unknown unit is rejected';
is convertTimeSinceString('1 day, 2 hours, 3 mins, 4 secs'), 93784, 'duration is parsed';
is convertToTimeSinceString(3661), '1 hour 1 minute 1 second', 'duration is formatted';
is canonicalizeReleaseName('Some.Show.S01E02.1080p.mkv'), 'some show s01e02 1080p', 'release name is canonicalized';
is stripMircColorCodes("\x0304,02red\x0f"), 'red', 'IRC formatting is removed';
is regexEscapeWildcardString('Show.*?'), 'Show\\..*.{1}', 'wildcards become a regular expression';

done_testing;
