#!/usr/bin/env perl
use strict;
use warnings;
use POSIX 'strftime';
use Text::CSV;
use File::ReadBackwards;
use Excel::Writer::XLSX;

my $file = $ARGV[0] or die "Please supply a CSV file as a script argument.\n";
my ( $out1, $out2, $out3 );
my $match1 = "Patch Installation Status";
my $match2 = "Number of Modified Patches by Classification";
my $csv1   = $match1 . ".csv";
my $csv2   = $match2 . ".csv";
my $date   = strftime '%Y-%m-%d', localtime;
my $xlsx   = "patch_status_" . $date . ".xlsx";

# open input file,reading backwards
#tie *BW, 'File::ReadBackwards', $file or die "Could not open '$file' $!\n";

#my $bw = File::ReadBackwards->new($file) or die "Could not open '$file' $!\n";

# open two output files
#open $out1, '>', "$csv1" or die "Could not open '$csv1' $!\n";
#open $out2, '>', "$csv2" or die "Could not open '$csv2' $!\n";
#open $out3, '>', "$xlsx" or die "Could not open '$xlsx' $!\n";
