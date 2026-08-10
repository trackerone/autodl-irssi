use 5.038;
use strict;
use warnings;
use Test::More;
use lib '.';
use AutodlIrssi::Bencoding;

my $root = parseBencodedString('d4:infod4:name11:Example.mkv6:lengthi42eee');
ok $root && $root->isDictionary, 'dictionary root is parsed';
my $info = $root->readDictionary('info');
ok $info->isDictionary, 'nested dictionary is parsed';
is $info->readDictionary('name')->{string}, 'Example.mkv', 'byte string is parsed';
is $info->readDictionary('length')->{integer}, 42, 'integer is parsed';

ok !defined parseBencodedString('l1:a1:be'), 'non-dictionary root is rejected';
ok !defined parseBencodedString('d3:key5:short'), 'truncated input is rejected';
ok !defined parseBencodedString('d3:keyxe'), 'invalid token is rejected';

done_testing;
