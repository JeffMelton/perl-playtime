$addaction = sub {
    my $command = shift;

    if ( $command =~ s#^/forecast ## && length($command) ) {
        my $post    = &get_post($command);
        my $api_key = "YOUR API KEY HERE";
        if ( !$post->{'id'} ) {
            &std("-- sorry, no such post (yet?): $command\n");
            return 1;
        }
        my $lat  = $post->{'_texapp_latitude'};
        my $long = $post->{'_texapp_longitude'};
        if ( !length($lat) || !length($long) ) {
            &std("-- sorry, no geoinformation in that post.\n");
            return 1;
        }

        my $ref = &grabjson("https://api.forecast.io/forecast/${api_key}/${lat},${long}");
		&std(   &descape( $ref->{'currently'}->{'summary'} ) . "\n"
			  . &descape( $ref->{'currently'}->{'temperature'} )
			  . "\x{00B0}F\n" ); # requires a Unicode escape sequence for the degree sign

        return 1;
    }

    return 0;
};
