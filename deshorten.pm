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

my $dirtyURL = $response->request->uri;
my $toBeCleaned = URI::URL->new($dirtyURL);
my $cleanURL = URI::URL->new();

$cleanURL->scheme( $toBeCleaned->scheme );
$cleanURL->host( $toBeCleaned->host );
$cleanURL->path( $toBeCleaned->path );

my $toOpen = $cleanURL->as_string();

if ( $response->is_success and $response->previous ) {
	print 'Redirects to: ', $toOpen, "\n";
}

my $continue = promptUser("Would you like to continue?", "y");

sub promptUser {

   #-------------------------------------------------------------------------#
   # promptUser, a Perl subroutine to prompt a user for input.
   # Copyright 2010 Alvin Alexander, http://www.devdaily.com
   # http://alvinalexander.com/perl/edu/articles/pl010005
   # This code is shared here under the
   # Creative Commons Attribution-ShareAlike Unported 3.0 license.
   # See http://creativecommons.org/licenses/by-sa/3.0/ for more information.
   #-------------------------------------------------------------------------#

	my ($promptString, $defaultValue) = @_;

    if ($defaultValue) {								# I don't think I need this logic, but if I peel out the if statement
		print qq{$promptString [$defaultValue]: };		# and leave just the print, it hangs ...
	}

	$| = 1;
	$_ = <STDIN>;

	chomp;

	if ($defaultValue) {
		return $_ ? $_ : $defaultValue;
	} else {
		return $_;
	}
	$continue = $_;
	return $continue;
}

if ($continue =~ m/y/i) {
	open_browser($toOpen);
}

exit 0;
