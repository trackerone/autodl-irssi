requires 'perl', '5.038';
requires 'Archive::Zip';
requires 'Digest::SHA';
requires 'HTML::Entities';
requires 'JSON';
requires 'Net::SSLeay';
requires 'XML::LibXML';

# Used by the development and CI test commands.
on 'test' => sub {
	requires 'Test::More';
};

# InternetUtils uses JSON and will automatically benefit when this optional
# implementation is present.
recommends 'JSON::XS';
