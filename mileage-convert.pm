#!/usr/bin/env perl
use strict;
use warnings;
use POSIX 'strftime';
use DateTime;
use Modern::Perl;
use Excel::Writer::XLSX;
use Text::CSV;
use Excel::Writer::XLSX::Utility;

my $file = $ARGV[0] or die "Please supply a CSV file as a script argument.\n";

my ( $out1, $csv1_ref );
my ( @csv0, @csv1 );
my $block1 = "Trip Logs";
my $block2 = "Locations";

# Delete the first 42 rows, as these aren't needed
system("sed -i.bak -e '1,42d' $file");

# open the initial input file
open( my $data, '<', $file ) or die "Could not open '$file' $!\n";

## Break up the input CSV into the pieces I need ##
# First reads the input file into an array, skipping blank lines
while ( my $line = <$data> ) {
    unless ( $line =~ /^$/ ) {
        chomp($line);
        $line =~ s/Tags/Customer/g;
        push( @csv0, $line );
    }
}

# convert the array to a string so I can split it
my $csv0 = join( "\n", @csv0 );

# split the string at regex match
my @blocks = split( /$block2/, $csv0 );

# convert the two strings back into arrays
@csv1 = split( "\n", $blocks[0] );

# remove first line from array
@csv1 = @csv1[ 1 .. $#csv1 ];

# open filehandles for writing data into
my $csv1      = $block1 . ".csv";
my $csv1_edit = $block1 . "-edited" . ".csv";

open $out1, '>', "$csv1" or die "Could not open '$csv1' $!\n";

# write the array to file, line by line
foreach (@csv1) {
    print $out1 "$_\n";
}

# close the file so I can reopen in the next step
close $out1;

open my $fh1, '<', $csv1 or die "Could not open '$csv1' $!\n";
open $out1, '>', "$csv1_edit" or die "Could not open '$csv1_edit' $!\n";

my $csv = Text::CSV->new( { binary => 1 } )
  or die "Cannot use CSV: " . Text::CSV->error_diag();

my @columns;
while (<$fh1>) {
    $csv->parse($_);
    my @data = $csv->fields();

    for my $i ( 0 .. $#data ) {
        push @{ $columns[$i] }, $data[$i];
    }
}

close $fh1;

my %hash = map { shift @$_ => $_ } @columns;
delete @hash{
    "Day", "Start Time", "End Time", "Activity", "From", "To", "Parking",
    "Tolls", "Notes", "Gap Between Trips (mi)", "Receipts"
};

# Create Excel workbook
my $month = DateTime->now->subtract( months => 1 )->truncate( to => 'month' );
my $strf_pattern = '%B';
my $date         = $month->strftime($strf_pattern);
my $xlsx         = $date . " Mileage" . ".xlsx";
my $workbook     = Excel::Writer::XLSX->new($xlsx);

# Create new worksheets
my $worksheet1 = $workbook->add_worksheet($block1);

# create format objects
# Default formatting
my $format = $workbook->add_format( border => 1 );

# Bold for headers
my $bold = $workbook->add_format( border => 1, bold => 1 );

# Double underline for total
my $underline = $workbook->add_format( bold => 1, underline => 34 );

# Define worksheet formatting
$worksheet1->set_column( 0, 8, 22 );

# write data to sheet
my ( $row, $col ) = ( 0, 0 );
my @order = (
    "Date",
    "Customer",
    "Beginning Odometer",
    "Ending Odometer",
    "Mileage (mi)"
);
foreach my $colname (@order) {
    $worksheet1->write_string( $row, $col, $colname, $bold );
    $worksheet1->write_col( $row + 1, $col, $hash{$colname}, $format );
    $col++;
}

# get number of rows
my $last_row = @csv1;

# translate to alphanumeric cell reference
my $last_cell = xl_rowcol_to_cell( $last_row - 1, 4 );

# write "Total" to cell
$worksheet1->write_string( $last_row + 1, 3, "Total", $underline );

# total mileage
$worksheet1->write_formula( $last_row + 1,
    4, "=SUM(E2:$last_cell)", $underline );

# clean up
my $cleanup = unlink $csv1, $csv1_edit;
