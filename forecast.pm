#!/usr/bin/env perl
##
# This module will grab your current location from your IP address, then
# will print to STDOUT some basic weather conditions and forecast.
#
# You'll need to sign up for your own forecast.io API key (line 25).
##

use strict;
use warnings;

use Forecast::IO;
use WWW::ipinfo;
use Data::Dumper;
use Math::Round;
use Ham::Resources::Utils qw ( compass );

my $ipinfo = get_ipinfo();
my $location = $ipinfo->{loc};
my @latlong = split(',', $location);
my $latitude = $latlong[0];
my $longitude = $latlong[1];
my $city = $ipinfo->{city};

my $api_key = "[YOUR_API_KEY_HERE]";

my $forecast = Forecast::IO->new(
  key       => $api_key,
  longitude => $longitude,
  latitude  => $latitude,
);

my %currently_data_points = %{ $forecast->{currently} };
my $precipProbability = $currently_data_points{'precipProbability'};

my $summary = lc $currently_data_points{'summary'};
my $currentTemp = round( $currently_data_points{'temperature'} );
my $windSpeed = round( $currently_data_points{'windSpeed'} );
my $windBearing = round( $currently_data_points{'windBearing'} );
my $compass = Ham::Resources::Utils->new();
my $cardinalBearing = $compass->compass($windBearing);

my @daily_data_points = @{ $forecast->{daily}->{data} };
my $temperatureMax = round( $daily_data_points[0]{temperatureMax} );
my $temperatureMin = round( $daily_data_points[0]{temperatureMin} );

print "It is " . $currentTemp . "°F and " . $summary . " in " . $city . ".\n";
print "The wind is " . $windSpeed . " mph from " . $cardinalBearing . ".\n";
print "Temperatures will range from a low of " . $temperatureMin . "°F to a high of " . $temperatureMax . "°F.\n";

if ($precipProbability lt 20) {
	exit 0;
} else {
	print "There is a " . $precipProbability . "% chance of precipitation.\n";
}
