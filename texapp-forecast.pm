$handle = sub {
    my $ref  = shift;
    my $lat  = $ref->{'_texapp_latitude'};
    my $long = $ref->{'_texapp_longitude'};
    my $time = $ref->{'created_at'};
	my $degree = "\x{2109}";

    return &defaulthandle unless ( length($lat) || length($long) );
    my $api_key = "YOUR API KEY HERE";
    my $data =
      &grabjson(
        "https://api.darksky.net/forecast/${api_key}/${lat},${long},${time}");
    my $current_conditions = $data->{'currently'}->{'summary'};
    my $current_temp       = $data->{'currently'}->{'temperature'};
    &std(
            &standardpostinteractive($ref) . "\t"
          . &descape($current_conditions) . "\n" . "\t"
          . &descape($current_temp)
          . $degree . "\n"
    );

    return 1;
};
