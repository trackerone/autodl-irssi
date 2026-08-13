.PHONY: test test-irssi test-http-401 test-https-stall test-http-incomplete-header test-tracker-update syntax check

test:
	prove -I. -r t

test-irssi:
	./t/integration/irssi-lifecycle.sh

test-http-401:
	./t/integration/http-401-retry.sh

test-https-stall:
	./t/integration/https-stall.sh

test-http-incomplete-header:
	./t/integration/http-incomplete-header.sh

test-tracker-update:
	./t/integration/tracker-update-install.sh

syntax:
	perl -I. -c AutodlIrssi/Bencoding.pm
	perl -I. -c AutodlIrssi/FilterState.pm
	perl -I. -c AutodlIrssi/LineBuffer.pm
	perl -I. -c AutodlIrssi/RtorrentCommands.pm
	perl -I. -c AutodlIrssi/TextUtils.pm

check: syntax test test-irssi test-http-401 test-https-stall test-http-incomplete-header test-tracker-update
