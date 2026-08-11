.PHONY: test test-irssi syntax check

test:
	prove -I. -r t

test-irssi:
	./t/integration/irssi-lifecycle.sh

syntax:
	perl -I. -c AutodlIrssi/Bencoding.pm
	perl -I. -c AutodlIrssi/FilterState.pm
	perl -I. -c AutodlIrssi/LineBuffer.pm
	perl -I. -c AutodlIrssi/RtorrentCommands.pm
	perl -I. -c AutodlIrssi/TextUtils.pm

check: syntax test test-irssi
