#!/usr/bin/env perl
use strict;
use warnings;
use POSIX 'strftime';
use Excel::Writer::XLSX;
use Text::CSV;
use Data::Dumper;

my $file = $ARGV[0] or die "Please supply a CSV file as a script argument.\n";

my ( $out1, $out2, $csv1_ref, $csv2_ref );
my ( @csv0, @csv1, @csv2 );
my $block1 = "Patch Installation Status";
my $block2 = "# of Modified Patches by Class";

# Delete the first 22 rows, as these aren't needed
system("sed -i.bak -e '1,22d' $file");

# open the initial input file
open( my $data, '<', $file ) or die "Could not open '$file' $!\n";

## Break up the input CSV into the pieces I need ##
# First reads the input file into an array, skipping blank lines
while ( my $line = <$data> ) {
    unless ( $line =~ /^$/ ) {
        chomp($line);
        push( @csv0, $line );
    }
}

# convert the array to a string so I can split it
my $csv0 = join( "\n", @csv0 );

# split the string at regex match
my @blocks = split( /$block1/, $csv0 );

# convert the two strings back into arrays
@csv1 = split( "\n", $blocks[1] );
@csv2 = split( "\n", $blocks[0] );

# remove first line from each array
@csv1 = @csv1[ 1 .. $#csv1 ];
@csv2 = @csv2[ 1 .. $#csv2 ];

# open filehandles for writing data into
my $csv1 = $block1 . ".csv";
my $csv2 = $block2 . ".csv";

open $out1, '>', "$csv1" or die "Could not open '$csv1' $!\n";
open $out2, '>', "$csv2" or die "Could not open '$csv2' $!\n";

# write the two arrays to file, line by line
foreach (@csv1) {
    print $out1 "$_\n";
}
foreach (@csv2) {
    # quick and dirty way to strip the block header left behind
    unless ( $_ =~ /$block2/ ) {
        print $out2 "$_\n";
    }
}

# close the files so I can reopen them in the next step
close $out1;
close $out2;

# get number of rows for later use
my $last_row1 = @csv1;

# get number of columns in header row for later use
my $header1 	 = join( ",", $csv1[1] );
my @header1      = split( ",", $header1 );
my $last_column1 = @header1;
my $header2      = join( ",", $csv2[1] );
my @header2      = split( ",", $header2 );
my $last_column2 = @header2;

## Process the new CSV files into XLSX ##
# reopen the CSV files I just made
open my $fh1, '<', $csv1 or die "Could not open '$csv1' $!\n";
open my $fh2, '<', $csv2 or die "Could not open '$csv2' $!\n";

my $csv1_out = Text::CSV->new( { binary => 1 } )
  or die "Cannot use CSV: " . Text::CSV->error_diag();
my $csv2_out = Text::CSV->new( { binary => 1 } )
  or die "Cannot use CSV: " . Text::CSV->error_diag();

# Create arrays of rows
my @rows1;
while ( my $row1 = $csv1_out->getline($fh1) ) {
    push @rows1, $row1;
}

# create array ref for XLSX writer
$csv1_ref = \@rows1;
$csv1_out->eof or $csv1_out->error_diag();
close $fh1;

my @rows2;
while ( my $row2 = $csv2_out->getline($fh2) ) {
    push @rows2, $row2;
}

# create array ref for XLSX writer
$csv2_ref = \@rows2;
$csv2_out->eof or $csv2_out->error_diag();
close $fh2;

# Create Excel workbook
my $date     = strftime '%Y-%m-%d', localtime;
my $xlsx     = "patch_status_" . $date . ".xlsx";
my $workbook = Excel::Writer::XLSX->new($xlsx);

# create format objects
# Default formatting
my $format = $workbook->add_format( border => 1 );
# Bold for headers
my $bold   = $workbook->add_format( border => 1, bold => 1 );
# Red for what needs attention
my $red    = $workbook->add_format( border => 1, bg_color => 'red', );

# Create new worksheets
my $worksheet1 = $workbook->add_worksheet($block1);
my $worksheet2 = $workbook->add_worksheet($block2);

# write hashrefs to worksheets
#$worksheet1->write_col( 0, 0, $csv1_ref, $format );
$worksheet2->write_col( 0, 0, $csv2_ref, $format );

# Define worksheet formatting
$worksheet2->set_row( 0, undef, $bold );
$worksheet2->set_column( 0, 8,  22 );
$worksheet1->autofilter( 0, 0, 0, 10 );
$worksheet1->filter_column( 'G', 'x == 0' );

# Hide rows that are of no concern
# Show and format the rest
my $hide_row = 0;
for my $hide_row_data ( @rows1 ) {
	my $installed = $hide_row_data->[6];
	if ( $installed eq 'Installed' ) {
		$worksheet1->set_row( 0, undef, $bold );
	} elsif ( $installed eq 0 ) {
		$worksheet1->set_row( $hide_row, undef, $red );
	} else {
		$worksheet1->set_row( $hide_row, undef, undef, 1 );
	}
	$worksheet1->write( $hide_row++, 0, $hide_row_data );
	$worksheet1->set_column( 0, 10, 22 );
}

