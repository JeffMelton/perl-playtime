#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use URI::URL;
use Browser::Open qw ( open_browser );

my $url = $ARGV[0];
my $dirty_url = long_url( $url );

sub long_url {
	my $ua = LWP::UserAgent->new;
	my $request = HTTP::Request->new( HEAD => $url );
	my $response = $ua->request($request);
	my $dirty_url = $response->request->uri;
	return $dirty_url;
}

my $clean_url = clean_url( $dirty_url );

sub clean_url {
	my $to_be_cleaned = URI::URL->new($dirty_url);
	my $scheme = $to_be_cleaned->scheme;
	my $host = $to_be_cleaned->host;
	my $path = $to_be_cleaned->path;
	my $clean_url = $scheme . "://" . $host . $path;
	return $clean_url;
}

print "The clean url is: " . $clean_url . "\n";
my $continue = prompt_user("Would you like to continue?", "y");

sub prompt_user {

	#-------------------------------------------------------------------------#
	# This subroutine heavily modified from:
	#
	# promptUser, a Perl subroutine to prompt a user for input.
	# Copyright 2010 Alvin Alexander, http://www.devdaily.com
	# http://alvinalexander.com/perl/edu/articles/pl010005
	# This code is shared here under the
	# Creative Commons Attribution-ShareAlike Unported 3.0 license.
	# See http://creativecommons.org/licenses/by-sa/3.0/ for more information.
	#-------------------------------------------------------------------------#

	my ($prompt_string, $default_value) = @_;

	print qq{$prompt_string [$default_value]: };

	$| = 1;
	$_ = <STDIN>;

	chomp;

	if ($default_value) {
		return $_ ? $_ : $default_value;
	} else {
		return $_;
	}
	$continue = $_;
	return $continue;
}

if ($continue =~ m/y/i) {
	open_browser($clean_url);
}

exit 0;
