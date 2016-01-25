#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use JSON qw(decode_json);
use URI::Escape;
use Net::IP;
use Net::Ping;
use Getopt::Long;
use MIME::Base64;
use Data::Dumper;

my $action;
my $api_key;
my $account_id;

my $usage = <<'END_MESSAGE';
Usage: $0
Required parameters:
	--account_id	<account id>
	--api_key		<api key>
	--action		< create_bucket | delete_bucket | list_buckets >
END_MESSAGE

GetOptions(
    'account_id=s' => \$account_id,
    'api_key=s'    => \$api_key,
    'action=s'     => \$action,
) or die "$usage\n";

my $authorize_endpoint =
  'https://api.backblaze.com/b2api/v1/b2_authorize_account';
my $create_endpoint = '/b2_create_bucket';
my $delete_endpoint = '/b2_delete_bucket';
my $list_endpoint   = '/b2_list_buckets';

my $ua = LWP::UserAgent->new();
my $token;
my $download_url;
my $api_url;

my $bucket_name;
my $bucket_type;
my $bucket_name_info;
my $bucket_type_info;
my $bucket_id;

if ( $action eq 'create_bucket' ) {

    $bucket_name_info = <<'END_MESSAGE';
bucketName (required)

Bucket names must be a minimum of 6 and a maximum of 50 characters long, and
must be globally unique; two different B2 accounts cannot have buckets with the
name name. Bucket names can consist of: letters, digits, and "-". Bucket names
cannot start with "b2-"; these are reserved for internal Backblaze use.
END_MESSAGE
    print $bucket_name_info;
    print "Please enter a bucket name: \n";
    chomp( $bucket_name = <> );

    $bucket_type_info = <<'END_MESSAGE';
bucketType (required)

Either "allPublic", meaning that files in this bucket can be downloaded by
anybody, or "allPrivate", meaning that you need a bucket authorization token to
download the files.
END_MESSAGE
    print $bucket_type_info;
    print "Please enter the bucket type: \n";
    chomp( $bucket_type = <> );

    unless ( $bucket_type eq 'allPublic' || 'allPrivate' ) {
        print $bucket_type_info;
    }

    &Authorize( $account_id, $api_key );
    &CreateBucket( $account_id, $bucket_name, $bucket_type );
}
elsif ( $action eq 'delete_bucket' ) {
    my $deleted = 0;
    do {
        print "Do you know the bucket ID? ";
        chomp( my $answer = <> );
        if ( $answer eq 'no' ) {
            print "Listing available buckets...\n";
            &Authorize( $account_id, $api_key );
            &ListBuckets($account_id);
        }
        elsif ( $answer eq 'yes' ) {
            print "Enter bucket ID: ";
            chomp( $bucket_id = <> );
            &Authorize( $account_id, $api_key );
            &DeleteBucket( $account_id, $bucket_id );
            $deleted = 1;
        }
        else {
            print "Please enter 'yes' or 'no'.\n";
        }
    } until ( $deleted eq 1 );
}
elsif ( $action eq 'list_buckets' ) {
    &Authorize( $account_id, $api_key );
    &ListBuckets($account_id);
}

sub Authorize {
    my $id_and_key         = $account_id . ":" . $api_key;
    my $basic_auth_string  = 'Basic ' . encode_base64($id_and_key);
    my @auth_header        = ( 'Authorization' => $basic_auth_string );
    my $authorize_response = $ua->get( $authorize_endpoint, @auth_header );
    if ( $authorize_response->is_success ) {
        my $content      = $authorize_response->decoded_content;
        my $content_data = decode_json( $authorize_response->decoded_content );
        $token        = $content_data->{authorizationToken};
        $download_url = $content_data->{downloadUrl};
        $api_url      = $content_data->{apiUrl} . "/b2api/v1";
    }
    else {
        print "Authorization failed.\n";
        print $authorize_response->request->as_string;
        print $authorize_response->as_string;
    }
    return;
}

sub CreateBucket {
    my $create_url =
        $api_url
      . $create_endpoint
      . "?accountId=$account_id"
      . "&bucketName=$bucket_name"
      . "&bucketType=$bucket_type";
    my @auth_header = ( 'Authorization' => $token );
    my $create_response = $ua->get( $create_url, @auth_header );
    if ( $create_response->is_success ) {
        my $content      = $create_response->decoded_content;
        my $content_data = decode_json( $create_response->decoded_content );
        print Dumper \$content_data;
    }
    else {
        print "create_bucket failed.\n";
        print $create_response->request->as_string;
        print $create_response->as_string;
    }
    return;
}

sub ListBuckets {
    my $list_url      = $api_url . $list_endpoint . "?accountId=$account_id";
    my @auth_header   = ( 'Authorization' => $token );
    my $list_response = $ua->get( $list_url, @auth_header );
    if ( $list_response->is_success ) {
        my $content      = $list_response->decoded_content;
        my $content_data = decode_json( $list_response->decoded_content );
        print Dumper \$content_data;
    }
    else {
        print "list_buckets failed\n";
        print $list_response->request->as_string;
        print $list_response->as_string;
    }
    return;
}

sub DeleteBucket {
    my $delete_url =
        $api_url
      . $delete_endpoint
      . "?accountId=$account_id"
      . "&bucketId=$bucket_id";
    my @auth_header = ( 'Authorization' => $token );
    my $delete_response = $ua->get( $delete_url, @auth_header );
    if ( $delete_response->is_success ) {
        my $content      = $delete_response->decoded_content;
        my $content_data = decode_json( $delete_response->decoded_content );
        print "Deleting bucket: $bucket_id ...\n";
        print Dumper \$content_data;
    }
    else {
        print "delete_bucket failed\n";
        print $delete_response->request->as_string;
        print $delete_response->as_string;
    }
    return;
}
