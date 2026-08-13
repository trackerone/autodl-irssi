use 5.038;
use strict;
use warnings;
use Test::More;

my $filename = 't/fixtures/tracker-update/v290.7.2-members.txt';
open my $fh, '<', $filename or die "Could not open '$filename': $!\n";
chomp(my @members = <$fh>);
close $fh or die "Could not close '$filename': $!\n";

is scalar @members, 78, 'verified v290.7.2 release member count';
ok !grep(m{/}, @members), 'release members are flat archive paths';
ok !grep(!/^[^\/]+\.tracker$/, @members), 'every release member is a tracker file';
is scalar(keys %{+{ map { $_ => 1 } @members }}), scalar(@members),
	'release member names are unique';
ok scalar(grep { $_ eq 'Upload.cx.tracker' } @members),
	'release manifest records Upload.cx absent from source master';

done_testing;
