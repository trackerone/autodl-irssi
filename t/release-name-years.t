use 5.038;
use strict;
use warnings;
use Test::More;
use lib '.';

BEGIN {
	package Irssi;
	sub import { }
	$INC{'Irssi.pm'} = __FILE__;
}

use AutodlIrssi::AnnounceParser;

sub release_info {
	my $release_name = shift;
	my %info;
	AutodlIrssi::AnnounceParser::extractReleaseNameInfo(\%info, $release_name);
	return \%info;
}

my $movie_2020 = release_info('Some.Movie.2020.1080p.BluRay.x264-GROUP');
is $movie_2020->{year}, 2020, '2020 is parsed as a movie year';
is $movie_2020->{name1}, 'Some Movie', '2020 separates a movie title from release metadata';

my $movie_2026 = release_info('Current.Movie.2026.2160p.WEB-DL.H265-GROUP');
is $movie_2026->{year}, 2026, 'current-decade movie year is parsed';
is $movie_2026->{name1}, 'Current Movie', 'current-decade year contributes to title extraction';

my $dated_tv = release_info('Daily.News.2026.08.15.1080p.HDTV.x264-GROUP');
is $dated_tv->{year}, 2026, 'current-decade year is retained for a dated TV release';
is $dated_tv->{ymd}, '2026 08 15', 'current-decade YYYY-MM-DD date is parsed';
is $dated_tv->{name1}, 'Daily News', 'current-decade date separates the TV title';

my $title_year = release_info('Doctor.Who.2005.S14E01.1080p.WEB-DL.x264-GROUP');
is $title_year->{year}, 2005, 'TV title year remains available as metadata';
is $title_year->{name1}, 'Doctor Who 2005', 'TV title year is not stripped before season metadata';

my $future_century = release_info('Future.Movie.2099.1080p.BluRay.x264-GROUP');
is $future_century->{year}, 2099, 'year parser does not expire at the next decade boundary';

my $not_a_year = release_info('Archive.2100.1080p.BluRay.x264-GROUP');
ok !defined $not_a_year->{year}, 'year parser remains bounded to the twentieth and twenty-first centuries';

done_testing;
