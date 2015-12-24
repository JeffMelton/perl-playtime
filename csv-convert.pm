#!/usr/bin/env perl
use strict;
use warnings;
use POSIX 'strftime';
use Text::CSV;
use Excel::Writer::XLSX;

my $file = $ARGV[0] or die "Please supply a CSV file as a script argument.\n";
my ( $out1, $out2, $out3 );
my ( @csv0, @csv1, @csv2 );
my $worksheet1 = "Patch Installation Status";
my $worksheet2 = "Number of Modified Patches by Classification";
my $csv1   = $worksheet1 . ".csv";
my $csv2   = $worksheet2 . ".csv";
my $date   = strftime '%Y-%m-%d', localtime;
my $xlsx   = "patch_status_" . $date . ".xlsx";

# DO NOT uncomment this until ready to roll!
# system("sed -i.bak -e '1,22d' $file");

# open input file
open (my $data, '<', $file) or die "Could not open '$file' $!\n";

# open output files
open $out1, '>', "$csv1" or die "Could not open '$csv1' $!\n";
open $out2, '>', "$csv2" or die "Could not open '$csv2' $!\n";
#open $out3, '>', "$xlsx" or die "Could not open '$xlsx' $!\n";

while (my $line = <$data>) {
	unless ($line =~ /^$/) {
		chomp($line);
		push (@csv0, $line);
	}
}

my $csv0 = join("\n", @csv0);
my @blocks = split(/$worksheet1/, $csv0);
@csv1 = split("\n", $blocks[1]);
@csv2 = split("\n", $blocks[0]);
foreach (@csv1) {
	print $out1 "$_\n";
}
foreach (@csv2) {
	unless ($_ =~ /$worksheet2/) {
		print $out2 "$_\n";
	}
}
