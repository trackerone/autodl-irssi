# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is IRC Auto Downloader
#
# The Initial Developer of the Original Code is
# David Nilsson.
# Portions created by the Initial Developer are Copyright (C) 2010, 2011
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#
# ***** END LICENSE BLOCK *****

#
# Updates the main program and tracker files
#

use 5.008;
use strict;
use warnings;

package AutodlIrssi::Updater;
use AutodlIrssi::Globals;
use AutodlIrssi::TextUtils;
use AutodlIrssi::FileUtils;
use AutodlIrssi::HttpRequest;
use AutodlIrssi::InternetUtils qw/ decodeJson /;
use AutodlIrssi::Dirs;
use AutodlIrssi::TrackerXmlParser;
use Digest::SHA qw/ sha256_hex /;
use File::Basename qw/ dirname /;
use File::Spec;
use File::Copy;
use File::Path qw/ rmtree /;
use File::Temp qw/ tempdir /;
use Archive::Zip qw/ :ERROR_CODES /;
use constant {
	AUTODL_UPDATE_URL => 'https://api.github.com/repos/autodl-community/autodl-irssi/releases/latest',
	TRACKERS_UPDATE_URL => 'https://api.github.com/repos/trackerone/autodl-irssi/releases?per_page=100',
	UPDATE_USER_AGENT => 'autodl-irssi',
};

sub new {
	my $class = shift;
	bless {
		handler => undef,
		request => undef,
		updateKind => undef,
		githubToken => $AutodlIrssi::g->{options}{githubToken},
	}, $class;
}

# Throws an exception if check() hasn't been called.
sub _verifyCheckHasBeenCalled {
	my $self = shift;
	die "update check hasn't been called!\n" unless $self->{autodl} || $self->{trackers};
}

# Returns true if we're checking for updates, or downloading something else
sub _isChecking {
	my $self = shift;

	# Vim Perl parser doesn't like !! so use 'not !' for now...
	return not !$self->{request};
}

# Notifies the handler, catching any exceptions. $self->{handler} will be undef'd.
sub _notifyHandler {
	my ($self, $errorMessage) = @_;

	eval {
		my $handler = $self->{handler};

		# Clean up before calling the handler
		$self->{handler} = undef;
		$self->{request} = undef;
		$self->{updateKind} = undef;

		if (defined $handler) {
			$handler->($errorMessage);
		}
	};
	if ($@) {
		chomp $@;
		message 0, "Updater::_notifyHandler: ex: $@";
	}
}

# Called when an error occurs. The handler is called with the error message.
sub _error {
	my ($self, $errorMessage) = @_;
	$errorMessage ||= "Unknown error";
	$self->_notifyHandler($errorMessage);
}

# Cancel any downloads, and call the handler with an error message.
sub cancel {
	my ($self, $errorMessage) = @_;

	$errorMessage ||= "Cancelled!";
	return unless $self->_isChecking();

	if ($self->{request}) {
		$self->{request}->cancel();
	}

	$self->_error($errorMessage);
}

sub _createHttpRequest {
	my $self = shift;

	$self->{request} = new AutodlIrssi::HttpRequest();
	$self->{request}->setUserAgent(UPDATE_USER_AGENT);
	$self->{request}->setFollowNewLocation();
}

sub _parseAutodlUpdate {
	my ($self, $autodlData) = @_;

	my $autodlTagName = my $autodlVersion = $autodlData->{tag_name};
	$autodlVersion =~ s/.*v//;
	my $autodlDownloadUrl = "https://github.com/autodl-community/autodl-irssi/releases/download/$autodlTagName/autodl-irssi-v$autodlVersion.zip";
	my $autodlChangeLog = $autodlData->{body};

	$self->{autodl} = {
		version		=> $autodlVersion,
		whatsNew	=> $autodlChangeLog,
		url			=> $autodlDownloadUrl,
	};

	$self->{autodl}{whatsNew} =~ s/\r//mg;
}

sub _parseTrackersUpdate {
	my ($self, $releases) = @_;

	die "Invalid trackers release list\n" unless ref $releases eq 'ARRAY';
	my ($trackersData) = grep {
		!$_->{draft} && !$_->{prerelease} &&
		defined $_->{tag_name} && $_->{tag_name} =~ /^trackers-v\d+(?:\.\d+)*$/
	} @$releases;
	die "Could not find a stable trackers release\n" unless $trackersData;

	my $trackersVersion = $trackersData->{tag_name};
	$trackersVersion =~ s/^trackers-v//;
	my $trackersAssetName = "autodl-trackers-v$trackersVersion.zip";
	my $trackersChecksumName = "$trackersAssetName.sha256";
	my ($trackersAsset) = grep {
		defined $_->{name} && $_->{name} eq $trackersAssetName
	} @{$trackersData->{assets} || []};
	die "Could not find trackers release asset '$trackersAssetName'\n"
		unless $trackersAsset && $trackersAsset->{browser_download_url};
	my ($trackersChecksum) = grep {
		defined $_->{name} && $_->{name} eq $trackersChecksumName
	} @{$trackersData->{assets} || []};
	die "Could not find trackers release checksum '$trackersChecksumName'\n"
		unless $trackersChecksum && $trackersChecksum->{browser_download_url};
	my $trackersDownloadUrl = $trackersAsset->{browser_download_url};
	my $trackersChangeLog = $trackersData->{body};

	$self->{trackers} = {
		version		=> $trackersVersion,
		whatsNew	=> $trackersChangeLog,
		url			=> $trackersDownloadUrl,
		assetName	=> $trackersAssetName,
		checksumUrl	=> $trackersChecksum->{browser_download_url},
	};

	$self->{trackers}{whatsNew} =~ s/\r//mg;
}

# Check for autodl updates. $handler->($errorMessage) will be notified.
sub checkAutodlUpdate {
	my ($self, $handler) = @_;

	die "Already checking for updates\n" if $self->_isChecking();

	$self->{handler} = $handler || sub {};
	$self->{updateKind} = 'autodl';
	$self->_createHttpRequest();

	$self->{updateUrl} = AUTODL_UPDATE_URL;

	my $headers = {};
	if ($self->{githubToken}) {
		$headers->{Authorization} = "token $self->{githubToken}";
	}

	$self->{request}->sendRequest("GET", "", $self->{updateUrl} , $headers, sub {
		$self->_onRequestReceived(@_);
	});
}

# Check for trackers updates. $handler->($errorMessage) will be notified.
sub checkTrackersUpdate {
	my ($self, $handler) = @_;

	die "Already checking for updates\n" if $self->_isChecking();

	$self->{handler} = $handler || sub {};
	$self->{updateKind} = 'trackers';
	$self->_createHttpRequest();

	$self->{updateUrl} = TRACKERS_UPDATE_URL;

	my $headers = {};
	if ($self->{githubToken}) {
		$headers->{Authorization} = "token $self->{githubToken}";
	}

	$self->{request}->sendRequest("GET", "", $self->{updateUrl} , $headers, sub {
		$self->_onRequestReceived(@_);
	});
}

sub _onRequestReceived {
	my ($self, $errorMessage) = @_;
	my $updateKind = $self->{updateKind};

	eval {
		return $self->_error("Error getting update info: $errorMessage") if $errorMessage;

		my $statusCode = $self->{request}->getResponseStatusCode();
		if ($statusCode != 200) {
			return $self->_error("Error getting update info: " . $self->{request}->getResponseStatusText());
		}

		my $jsonData = decodeJson($self->{request}->getResponseData());

		if ($updateKind && $updateKind eq 'autodl') {
			$self->_parseAutodlUpdate($jsonData);
		}
		elsif ($updateKind && $updateKind eq 'trackers') {
			$self->_parseTrackersUpdate($jsonData);
		}
		else {
			die "Unknown update kind\n";
		}

		$self->_notifyHandler("");
	};
	if ($@) {
		chomp $@;
		if ($updateKind && $updateKind eq 'autodl') {
			$self->_error("Could not parse autodl update data: $@");
		}
		elsif ($updateKind && $updateKind eq 'trackers') {
			$self->_error("Could not parse trackers update data: $@");
		}
		else {
			$self->_error("Could not parse update data: $@");
		}
	}
}

# Download, validate, and install the trackers file in $destDir. check() must've been called successfully.
sub updateTrackers {
	my ($self, $destDir, $handler) = @_;

	$self->_verifyCheckHasBeenCalled();
	die "Already checking for trackers updates\n" if $self->_isChecking();

	$self->{handler} = $handler || sub {};
	$self->_createHttpRequest();
	$self->{request}->sendRequest("GET", "", $self->{trackers}{checksumUrl}, {}, sub {
		$self->_onDownloadedTrackersChecksum(@_, $destDir);
	});
}

sub _onDownloadedTrackersChecksum {
	my ($self, $errorMessage, $destDir) = @_;

	eval {
		return $self->_error("Error getting trackers checksum: $errorMessage") if $errorMessage;

		my $statusCode = $self->{request}->getResponseStatusCode();
		if ($statusCode != 200) {
			return $self->_error("Error getting trackers checksum: " . $self->{request}->getResponseStatusText());
		}

		my $assetName = $self->{trackers}{assetName};
		my $checksumData = $self->{request}->getResponseData();
		die "Invalid checksum data\n"
			unless $checksumData =~ /^([0-9a-fA-F]{64})\s+\*?\Q$assetName\E\s*$/;
		$self->{trackers}{checksum} = lc $1;

		$self->_createHttpRequest();
		$self->{request}->sendRequest("GET", "", $self->{trackers}{url}, {}, sub {
			$self->_onDownloadedTrackersFile(@_, $destDir);
		});
	};
	if ($@) {
		chomp $@;
		$self->_error("Error validating trackers checksum: $@");
	}
}

sub _onDownloadedTrackersFile {
	my ($self, $errorMessage, $destDir) = @_;

	eval {
		return $self->_error("Error getting trackers file: $errorMessage") if $errorMessage;

		my $statusCode = $self->{request}->getResponseStatusCode();
		if ($statusCode != 200) {
			return $self->_error("Error getting trackers file: " . $self->{request}->getResponseStatusText());
		}

		my $zipData = $self->{request}->getResponseData();
		my $expectedChecksum = $self->{trackers}{checksum};
		die "Trackers checksum was not downloaded\n" unless $expectedChecksum;
		my $actualChecksum = sha256_hex($zipData);
		die "Trackers checksum mismatch (expected $expectedChecksum, got $actualChecksum)\n"
			unless $actualChecksum eq $expectedChecksum;

		$self->_installTrackerZip($zipData, $destDir);

		$self->_notifyHandler("");
	};
	if ($@) {
		chomp $@;
		$self->_error("Error downloading trackers file: $@");
	}
}

sub _installTrackerZip {
	my ($self, $zipData, $destDir) = @_;

	my $tmp;
	my $stageDir;
	my $error;
	eval {
		$tmp = createTempFile();
		binmode $tmp->{fh};
		print { $tmp->{fh} } $zipData or die "Could not write to temporary file\n";
		close $tmp->{fh};

		my $zip = new Archive::Zip();
		my $code = $zip->read($tmp->{filename});
		die "Could not read zip file, code: $code, size: " . length($zipData) . "\n"
			if $code != AZ_OK;

		my @members = $zip->members();
		die "Tracker archive is empty\n" unless @members;
		my %memberNames;
		for my $member (@members) {
			my $memberName = $member->fileName();
			die "Invalid tracker archive member '$memberName'\n"
				if $member->isDirectory() || $memberName !~ /^[A-Za-z0-9][A-Za-z0-9._ -]*\.tracker$/;
			my $canonicalName = lc $memberName;
			die "Duplicate tracker archive member '$memberName'\n"
				if $memberNames{$canonicalName}++;
		}

		die "Could not create tracker directory '$destDir'\n" unless createDirectories($destDir);
		$stageDir = tempdir('.autodl-trackers-stage-XXXXXX', DIR => dirname($destDir), CLEANUP => 0);
		my %trackerTypes;
		for my $member (@members) {
			my $memberName = $member->fileName();
			my $stageFile = File::Spec->catfile($stageDir, $memberName);
			die "Could not extract tracker file '$memberName'\n"
				unless $member->extractToFileNamed($stageFile) == AZ_OK;
			my $trackerInfo = new AutodlIrssi::TrackerXmlParser()->parse($stageFile);
			my $trackerType = $trackerInfo->{type};
			die "Tracker file '$memberName' has no type\n"
				unless defined $trackerType && $trackerType ne '';
			die "Duplicate tracker type '$trackerType'\n" if $trackerTypes{$trackerType}++;
		}

		$self->_replaceTrackerFiles($stageDir, $destDir, [map { $_->fileName() } @members]);
	};
	$error = $@;
	if ($tmp) {
		close $tmp->{fh};
		unlink $tmp->{filename};
	}
	rmtree($stageDir) if $stageDir && -d $stageDir;
	die $error if $error;
}

sub _replaceTrackerFiles {
	my ($self, $stageDir, $destDir, $memberNames) = @_;

	my $backupDir = tempdir('.autodl-trackers-backup-XXXXXX', DIR => dirname($destDir), CLEANUP => 0);
	my @backedUp;
	my @installed;
	my $installError;
	eval {
		for my $oldFile ($AutodlIrssi::g->{trackerManager}->getTrackerFiles($destDir)) {
			my (undef, undef, $fileName) = File::Spec->splitpath($oldFile);
			my $backupFile = File::Spec->catfile($backupDir, $fileName);
			move($oldFile, $backupFile) or die "Could not back up tracker file '$oldFile': $!\n";
			push @backedUp, [$backupFile, $oldFile];
		}

		for my $memberName (@$memberNames) {
			my $stageFile = File::Spec->catfile($stageDir, $memberName);
			my $destFile = File::Spec->catfile($destDir, $memberName);
			$self->_installStagedTrackerFile($stageFile, $destFile);
			push @installed, $destFile;
		}
	};
	$installError = $@;
	if (!$installError) {
		rmtree($backupDir);
		return;
	}

	my @rollbackErrors;
	for my $installedFile (reverse @installed) {
		push @rollbackErrors, "Could not remove '$installedFile': $!"
			unless unlink $installedFile;
	}
	for my $backup (reverse @backedUp) {
		my ($backupFile, $oldFile) = @$backup;
		push @rollbackErrors, "Could not restore '$oldFile': $!"
			unless move($backupFile, $oldFile);
	}

	if (@rollbackErrors) {
		die $installError . "Rollback failed; backup retained in '$backupDir': " . join('; ', @rollbackErrors) . "\n";
	}
	rmtree($backupDir);
	die $installError;
}

sub _installStagedTrackerFile {
	my ($self, $stageFile, $destFile) = @_;
	move($stageFile, $destFile) or die "Could not install tracker file '$destFile': $!\n";
}

# Download the autodl file and extract it to $destDir. check() must've been called successfully.
sub updateAutodl {
	my ($self, $destDir, $handler) = @_;

	$self->_verifyCheckHasBeenCalled();
	die "Already checking for autodl updates\n" if $self->_isChecking();

	$self->{handler} = $handler || sub {};
	$self->_createHttpRequest();
	$self->{request}->sendRequest("GET", "", $self->{autodl}{url}, {}, sub {
		$self->_onDownloadedAutodlFile(@_, $destDir);
	});
}

sub _onDownloadedAutodlFile {
	my ($self, $errorMessage, $destDir) = @_;

	eval {
		return $self->_error("Error getting autodl file: $errorMessage") if $errorMessage;

		my $statusCode = $self->{request}->getResponseStatusCode();
		if ($statusCode != 200) {
			return $self->_error("Error getting autodl file: " . $self->{request}->getResponseStatusText());
		}

		$self->_extractZipFile($self->{request}->getResponseData(), $destDir);

		# If autorun/autodl-irssi.pl exists, update it.
		my $srcAutodlFile = File::Spec->catfile($destDir, 'autodl-irssi.pl');
		my $dstAutodlFile = File::Spec->catfile($destDir, 'autorun', 'autodl-irssi.pl');
		if (-f $dstAutodlFile) {
			copy($srcAutodlFile, $dstAutodlFile) or die "Could not create '$dstAutodlFile': $!\n";
		}

		$self->_notifyHandler("");
	};
	if ($@) {
		chomp $@;
		$self->_error("Error downloading autodl file: $@");
	}
}

sub _extractZipFile {
	my ($self, $zipData, $destDir) = @_;

	my $tmp;
	eval {
		$tmp = createTempFile();
		binmode $tmp->{fh};
		print { $tmp->{fh} } $zipData or die "Could not write to temporary file\n";
		close $tmp->{fh};

		my $zip = new Archive::Zip();
		my $code = $zip->read($tmp->{filename});
		if ($code != AZ_OK) {
			die "Could not read zip file, code: $code, size: " . length($zipData) . "\n";
		}

		my @fileInfos = map {
			{
				destFile => appendUnixPath($destDir, $_->fileName()),
				member => $_,
			}
		} $zip->members();

		# Make sure we can write to all files
		for my $info (@fileInfos) {
			message 5, "Creating file '$info->{destFile}'";

			if ($info->{member}->isDirectory()) {
				die "Could not create directory '$info->{destFile}'\n" unless createDirectories($info->{destFile});
			}
			else {
				my ($volume, $dir, $file) = File::Spec->splitpath($info->{destFile}, 0);
				die "Could not create directory '$dir'\n" unless createDirectories($dir);
				open my $fh, '>>', $info->{destFile} or die "Could not write to file '$info->{destFile}': $!\n";
				close $fh;
			}
		}

		for my $trackerFile ($AutodlIrssi::g->{trackerManager}->getTrackerFiles(getTrackerFilesDir())) {
			message 5, "Deleting file $trackerFile";
			unlink $trackerFile;
		}

		# Now write all data to disk. This shouldn't fail... :)
		for my $info (@fileInfos) {
			if (!$info->{member}->isDirectory()) {
				message 5, "Extracting file '$info->{destFile}'";
				if ($info->{member}->extractToFileNamed($info->{destFile}) != AZ_OK) {
					die "Could not extract file '$info->{destFile}'\n";
				}
			}
		}
	};
	if ($tmp) {
		close $tmp->{fh};
		unlink $tmp->{filename};
	}
	die $@ if $@;
}

sub getAutodlWhatsNew {
	return shift->{autodl}{whatsNew};
}

# Returns true if there's an autodl update available
sub hasAutodlUpdate {
	my ($self, $version) = @_;

	$self->_verifyCheckHasBeenCalled();

	my @localInfo = split(/\./, $version);
	my @updateInfo = split(/\./, $self->{autodl}{version});

	my $maxIndex = scalar @localInfo > scalar @updateInfo ? scalar @localInfo - 1 : scalar @updateInfo - 1;

	for my $i (0 .. $maxIndex) {
		my $localPart = $localInfo[$i] ? $localInfo[$i] : '0';
		my $updatePart = $updateInfo[$i] ? $updateInfo[$i] : '0';

		return 1 if ($updatePart > $localPart);
	}

	return 0;
}

sub getTrackersWhatsNew {
	return shift->{trackers}{whatsNew};
}

# Returns true if there's a trackers update available
sub hasTrackersUpdate {
	my ($self, $version) = @_;

	$self->_verifyCheckHasBeenCalled();
	return $self->getTrackersVersion() gt $version;
}

sub getTrackersVersion {
	my $self = shift;

	$self->_verifyCheckHasBeenCalled();
	return $self->{trackers}{version};
}

# Returns true if we're sending a request
sub isSendingRequest {
	return shift->_isChecking();
}

1;
