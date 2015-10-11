#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use URI::URL;
use Browser::Open qw ( open_browser );

my $url = $ARGV[0];
my $ua = LWP::UserAgent->new;
my $request = HTTP::Request->new( HEAD => $url );
my $response = $ua->request($request);

my $dirty_url = $response->request->uri;
my $to_be_cleaned = URI::URL->new($dirty_url);
my $clean_url = URI::URL->new();

$clean_url->scheme( $to_be_cleaned->scheme );
$clean_url->host( $to_be_cleaned->host );
$clean_url->path( $to_be_cleaned->path );

my $to_open = $clean_url->as_string();

if ( $response->is_success and $response->previous ) {
	print 'Redirects to: ', $to_open, "\n";
}

my $continue = prompt_user("Would you like to continue?", "y");

sub prompt_user {

	#-------------------------------------------------------------------------#
	# prompt_user, a Perl subroutine to prompt a user for input.
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
	open_browser($to_open);
}

exit 0;
