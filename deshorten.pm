#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use Browser::Open qw ( open_browser );

my $url = $ARGV[0];
my $ua = LWP::UserAgent->new;
my $request = HTTP::Request->new( HEAD => $url );
my $response = $ua->request($request);

if ( $response->is_success and $response->previous ) {
  print $request->url, ' redirected to ', $response->request->uri, "\n";
}

open_browser($response->request->uri);
