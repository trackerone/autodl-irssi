.PHONY: test test-irssi test-http-401 syntax check

test:
	prove -I. -r t

test-irssi:
	./t/integration/irssi-lifecycle.sh

test-http-401:
	./t/integration/http-401-retry.sh

syntax:
	perl -I. -c AutodlIrssi/Bencoding.pm
	perl -I. -c AutodlIrssi/FilterState.pm
	perl -I. -c AutodlIrssi/LineBuffer.pm
	perl -I. -c AutodlIrssi/RtorrentCommands.pm
	perl -I. -c AutodlIrssi/TextUtils.pm

check: syntax test test-irssi test-http-401
