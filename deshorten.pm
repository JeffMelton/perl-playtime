#!/usr/bin/env perl
use strict;
use warnings;

use JSON;
use URI::URL;
use REST::Client;
use Modern::Perl;
use Term::ReadKey;
use LWP::UserAgent;
use Mojo::UserAgent;
use Browser::Open qw ( open_browser );

my $token;
my $prompt;
my $continue;
my $dirty_url;
my $clean_url;
my $source_link;
my $access_token;
my $url          = $ARGV[0];
my $client       = REST::Client->new();
my $redirect_uri = 'https://getpocket.com/a/queue';
my $consumer_key = '<your Pocket API key';

sub long_url {
    my $ua = LWP::UserAgent->new;
    $ua->agent(
        'Mozilla/5.0 (X11; Ubuntu; Linux i686) Gecko/20071127 Firefox/2.0.0.11'
    );
    my $request   = HTTP::Request->new( HEAD => $url );
    my $response  = $ua->request($request);
    my $dirty_url = $response->request->uri;
    return $dirty_url;
}

sub clean_url {
    my $to_be_cleaned = URI::URL->new($dirty_url);
    my $scheme        = $to_be_cleaned->scheme;
    my $host          = $to_be_cleaned->host;
    $host =~ s/(^m\.)|(^mobile\.)//;
    my $path = $to_be_cleaned->path;
    $clean_url = $scheme . "://" . $host . $path;
    return $clean_url;
}

sub source_link {
    my $ua = Mojo::UserAgent->new;
    $ua->get($clean_url)->res->dom->find('.story-sourcelnk')->grep(
        sub {
            $source_link = shift->{href};
            return $source_link;
        }
    );
    return $source_link;
}

sub pocket {
    $client->setHost('https://getpocket.com/v3');
    $client->addHeader( 'Content-Type', 'application/json' );
    $client->addHeader( 'X-Accept',     'application/json' );

    sub getToken {
        my %request_body = (
            'consumer_key' => "$consumer_key",
            'redirect_uri' => "$redirect_uri"
        );
        my $request_body = encode_json \%request_body;
        $client->POST( '/oauth/request', $request_body );
        my $response = from_json( $client->responseContent() );
        $token = $response->{'code'};
        return $token;
    }

    sub authorizeApp {
        open_browser(
"https://getpocket.com/auth/authorize?request_token=$token&redirect_uri=$redirect_uri"
        );
        sleep(2);

        my %authorize_body = (
            'consumer_key' => "$consumer_key",
            'code'         => "$token"
        );
        my $authorize_body = encode_json \%authorize_body;

        $client->POST( '/oauth/authorize', $authorize_body )->responseContent();
        my $response = from_json( $client->responseContent() );
        $access_token = $response->{'access_token'};
        my $username = $response->{'username'};
        return $access_token;
    }

    sub addLink {
        my %add_body = (
            'consumer_key' => "$consumer_key",
            'access_token' => "$access_token",
            'url'          => "$clean_url"
        );
        my $add_body = encode_json \%add_body;

        $client->POST( '/add', $add_body );
        my $response = $client->responseContent();
        return $response;
    }

    $token = &getToken;
    $access_token = &authorizeApp( $token, $consumer_key, $redirect_uri );
    print "Adding $clean_url to Pocket.\n";
    &addLink( $access_token, $consumer_key, $clean_url );
    return;
}

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

    my ( $prompt_string, $default_value ) = @_;

    print qq{$prompt_string [$default_value]: };

    $| = 1;

	ReadMode 4;
	#$_ = <STDIN>;
	#chomp;
	my $key;
	while (not defined ($key = ReadKey(-1))) {
	}
	ReadMode 0;


    if ($default_value) {
		#return $_ ? $_ : $default_value;
		return $key ? $key : $default_value;
    }
    else {
		#return $_;
		return $key;
    }
	#$continue = $_;
	$continue = $key;
    return $continue;
}

$dirty_url = long_url($url);
$clean_url = clean_url($dirty_url);

if ( $clean_url =~ /slashdot/ ) {
    $clean_url = source_link($clean_url);
}
elsif ( $clean_url =~ /wired/ ) {
	$prompt = prompt_user( "Send Wired link to Pocket?", "y" );
	if ( $prompt =~ m/n/i ) {
		exit 0;
	}
	else {
		pocket($clean_url);
		exit 0;
	}
}

print "The source url is: " . $clean_url . "\n";

$continue = prompt_user( "(O)pen, (P)ocket, or (C)ancel?", "c" );

if ( $continue =~ m/p/i ) {
    pocket($clean_url);
	print "\n";
}
elsif ( $continue =~ m/c/i ) {
    exit 0;
}
else {
    open_browser($clean_url);
	print "\n";
}

exit 0;
