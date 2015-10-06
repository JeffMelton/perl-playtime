#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use Browser::Open qw ( open_browser );

my $url = $ARGV[0];
my $ua = LWP::UserAgent->new;
my $request = HTTP::Request->new( HEAD => $url );
my $response = $ua->request($request);
my $continue = promptUser();

if ( $response->is_success and $response->previous ) {
  print $request->url, ' redirected to ', $response->request->uri, "\n";
  promptUser("Would you like to continue? ");
  if ($continue =~ m/y/i) {
  	open_browser($response->request->uri);
  }
}

sub promptUser {

   #-------------------------------------------------------------------------#
   # promptUser, a Perl subroutine to prompt a user for input.
   # Copyright 2010 Alvin Alexander, http://www.devdaily.com
   # This code is shared here under the
   # Creative Commons Attribution-ShareAlike Unported 3.0 license.
   # See http://creativecommons.org/licenses/by-sa/3.0/ for more information.
   #-------------------------------------------------------------------------#

   #-------------------------------------------------------------------#
   #  two possible input arguments - $promptString, and $defaultValue  #
   #  make the input arguments local variables.                        #
   #-------------------------------------------------------------------#

   my($promptString,$defaultValue) = @_;
   $defaultValue ||= "y";

   #-------------------------------------------------------------------#
   #  if there is a default value, use the first print statement; if   #
   #  no default is provided, print the second string.                 #
   #-------------------------------------------------------------------#

   if ($defaultValue) {
      print $promptString, "[", $defaultValue, "]: ";
   } else {
      print $promptString, ": ";
   }

   $| = 1;               # force a flush after our print
   $_ = <STDIN>;         # get the input from STDIN (presumably the keyboard)


   #------------------------------------------------------------------#
   # remove the newline character from the end of the input the user  #
   # gave us.                                                         #
   #------------------------------------------------------------------#

   chomp;

   #-----------------------------------------------------------------#
   #  if we had a $default value, and the user gave us input, then   #
   #  return the input; if we had a default, and they gave us no     #
   #  no input, return the $defaultValue.                            #
   #                                                                 #
   #  if we did not have a default value, then just return whatever  #
   #  the user gave us.  if they just hit the <enter> key,           #
   #  the calling routine will have to deal with that.               #
   #-----------------------------------------------------------------#

   if ("$defaultValue") {
      return $_ ? $_ : $defaultValue;    # return $_ if it has a value
   } else {
      return $_;
   }
}

exit 0;
