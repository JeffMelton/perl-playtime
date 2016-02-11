#!/usr/bin/env perl

use warnings;
no warnings "experimental";

use Net::IP;
use Net::Ping;
use URI::Escape;
use Term::ReadKey;
use LWP::UserAgent;
use Config::Properties;
use feature qw(switch);
use JSON qw(decode_json);
use Pod::Usage qw(pod2usage);
use Getopt::Long qw(GetOptions);
use HTTP::Request::Common qw(POST);

my $vmid;
my $help;
my $status;
my $action;
my $manual;
my %options;
my $hostname;
my $hostpass;
my $nodes_endpoint   = '/nodes';
my $pools_endpoint   = '/pools';
my $storage_endpoint = '/storage';
my $cluster_endpoint = '/cluster';
my $access_endpoint  = '/access/ticket';
my $properties_file  = 'proxmox.properties';
my $api_host         = 'https://{your host here}/api2/json';

GetOptions(
    \%options,
    'a|action:s' => \$action,
    'help|h'     => \$help,
    'manual|man' => \$manual,
) || pod2usage( -verbose => 2 );

pod2usage( -verbose => 1 ) if $help;
pod2usage( -verbose => 2 ) if $manual;
pod2usage( -verbose => 2, -message => "$0: Too many arguments.\n" )
  if ( @ARGV > 1 );
pod2usage(
    {
        -message => "Syntax error.",
        -verbose => 2,
        -exitval => 2,
        -output  => \*STDERR
    }
) unless ( defined( $action || $help || $manual ) );

if ( !-f $properties_file ) {
    die "Property file " . $properties_file . " not found.\n";
}

open( PROPS, '<', $properties_file )
  or die "Unable to open " . $properties_file;
my $props = new Config::Properties();
$props->load(*PROPS);

my $user     = $props->getProperty("user");
my $password = $props->getProperty("password");

if (   !defined $user
    || $user eq ""
    || !defined $password
    || $password eq "" )
{
    die "Missing values for user or password properties.\n";
}

# my %ssl_opts = (
# ssl_opts => {
# SSL_verify_mode => SSL_VERIFY_NONE,
# verify_hostname => 0,
# },
# );
# my $ua = LWP::UserAgent->new(%ssl_opts);
my $ua = LWP::UserAgent->new();

my $next_ip;
my $next_id;
my $pve_auth_cookie;
my @pve_auth_cookie;
my $csrf_prevention_token;
my @csrf_prevention_token;

my $query = <<'QUERY';
Do you want to check the status of:
1) one container or,
2) all containers?
QUERY
my $ip_range = "xxx.xxx.xxx.";
my @ip_block = qw( xxx xxx xxx xxx xxx xxx xxx );

# Parse arguments to call action subroutines
given ($action) {
    when (/nextid/i) {
        &NextID( $user, $password, @pve_auth_cookie );
    }
    when (/nextip/i) {
        &NextIP( $user, $password );
    }
    when (/create/i) {
        my $response;
        {
            print "Do you know the VM ID you'd like to use (yes or no)? ";
            chomp( $response = <> );
            redo unless $response =~ /yes|no/i;
        }
        if ( $response =~ /no/i ) {
            &NextID( $user, $password, @pve_auth_cookie );
        }
        else {
            {
                print "What container number would you like to use? ";
                chomp( $vmid = <> );
                redo unless ( length $vmid > 0 );
                &Validate($vmid);
            }
            $next_id = $vmid;
        }
        print "Enter the hostname: ";
        chomp( $hostname = <> );
        print "Enter the root password (will not echo): ";
        ReadMode( noecho => STDIN );
        chomp( $hostpass = <> );
        print "\n";
        ReadMode( restore => STDIN );
        &NextIP( $user, $password );
        $vmid = $next_id;
        &Create( $user, $password, $hostname, $hostpass, $lowest_node,
            $next_id, $next_ip, %net0 );
        do {
            sleep(15);
            &StatusOne( $user, $password, $vmid );
        } until ( defined $status );
        print "Would you like to start the VM now? ";
        chomp( $response = <> );
        if ( $response eq 'yes' ) {
            &Start( $user, $password, $vmid );
        }
        else {
            exit 1;
        }
    }
    when (/delete/i) {
        print "What container ID would you like to delete? ";
        chomp( $vmid = <> );
        redo unless ( length $vmid > 0 );
        &Validate($vmid);
        &StatusOne( $user, $password, $vmid );
        &Delete( $user, $password, $vmid, $status );
    }
    when (/status/i) {
        my $response;
        {
            print $query;
            print "Enter 1 or 2: ";
            chomp( $response = <> );
            redo unless ( length $response eq 1 && $response =~ /[12]/ );
        }
        if ( $response == 1 ) {
            print "What container status would you like to check? ";
            chomp( $vmid = <> );
            redo unless ( length $vmid > 0 );
            &Validate($vmid);
            &StatusOne( $user, $password, $vmid );
        }
        else {
            &StatusAll( $user, $password );
        }
    }
    when (/start/i) {
        print "What container ID would you like to start? ";
        chomp( $vmid = <> );
        redo unless ( length $vmid > 0 );
        &Validate($vmid);
        &StatusOne( $user, $password, $vmid );
        &Start( $user, $password, $vmid, $status );
    }
    when (/stop/i) {
        print "What container ID would you like to stop? ";
        chomp( $vmid = <> );
        redo unless ( length $vmid > 0 );
        &Validate($vmid);
        &StatusOne( $user, $password, $vmid );
        &Stop( $user, $password, $vmid, $status );
    }
}

# Get access ticket
sub Access {
    my $access_url =
      $api_host . $access_endpoint . "?username=$user" . "&password=$password";
    my $access_response = $ua->post($access_url);
    if ( $access_response->is_success ) {
        my $login_ticket_data =
          decode_json( $access_response->decoded_content );
        my $ticket = $login_ticket_data->{data};
        $pve_auth_cookie       = $ticket->{ticket};
        $csrf_prevention_token = $ticket->{CSRFPreventionToken};
    }
    else {
        print "Access failed.\n";
        my $login_ticket_data =
          decode_json( $access_response->decoded_content );
        print $access_response->request->as_string;
        print $access_response->as_string;
    }
    @pve_auth_cookie = ( 'Cookie' => 'PVEAuthCookie=' . $pve_auth_cookie );
    @csrf_prevention_token =
      ( 'CSRFPreventionToken' => $csrf_prevention_token );
    return;
}

# Check node usage
sub Usage {
    &Access( $user, $password );
    my $usage_url = $api_host . $cluster_endpoint . "/resources?type=node";
    my $usage_response = $ua->get( $usage_url, @pve_auth_cookie );
    if ( $usage_response->is_success ) {
        my %resource_hash = ();
        my $usage_data    = decode_json( $usage_response->decoded_content );
        foreach my $node ( @{ $usage_data->{data} } ) {
            my $node_name = $node->{node};
            my $node_usage_url =
              $api_host . $nodes_endpoint . "/$node_name/status";
            my $node_usage_response =
              $ua->get( $node_usage_url, @pve_auth_cookie );
            if ( $node_usage_response->is_success ) {
                my $node_usage_data =
                  decode_json( $node_usage_response->decoded_content );
                my $node_memory_usage;
                foreach my $node_usage ( $node_usage_data->{data} ) {
                    $node_memory_usage = $node_usage->{memory}{used};
                    my $node_load_average = sprintf(
                        "%.2f",
                        (
                            $node_usage->{loadavg}->[0] +
                              $node_usage->{loadavg}->[1] +
                              $node_usage->{loadavg}->[2]
                        ) / 3
                    );
                }
                $resource_hash{$node_name} = $node_memory_usage;
            }
            else {
                print "Failed to get single node usage.\n";
                print $node_usage_response->request->as_string;
                print $node_usage_response->as_string;
            }
        }
        my @lowest_usage;
        foreach $key (
            sort { $resource_hash{$a} <=> $resource_hash{$b} }
            keys %resource_hash
          )
        {
            push( @lowest_usage, $key );
        }
        $lowest_node = shift @lowest_usage;
    }
    else {
        print "Failed to get cluster usage.\n";
        print $usage_response->request->as_string;
        print $usage_response->as_string;
    }
    return;
}

# Validate container ID
sub Validate {
    {
        redo unless ( $vmid >= 100 );
    }
}

# Create a new container
sub Create {
    &Access( $user, $password );
    my %net0 = (
        bridge => 'vmbr0',
        name   => 'eth0',
        gw     => '{your gateway here}',
        ip6    => 'dhcp',
    );
    my @net0;
    for my $key ( keys %net0 ) {
        push @net0, join "=", map { uri_escape($_) } $key, $net0{$key};
    }
    local $net0 = join ",", @net0;

    # have to double-encode these params, then push onto the create args
    $net0 = uri_escape($net0);

    # has to be url-encoded separately, then added to the net0 params
    my $ip = ',ip=' . $next_ip;
    $ip   = uri_escape($ip);
    $net0 = $net0 . $ip;

    my %create_args = (
        vmid       => $next_id,
        hostname   => $hostname,
        storage    => 'local',
        password   => $hostpass,
        ostemplate => 'local:vztmpl/debian-8.0-standard_8.0-1_amd64.tar.gz',
    );
    my @create_args;
    for my $key ( keys %create_args ) {
        push @create_args, join "=", map { uri_escape($_) } $key,
          $create_args{$key};
    }
    local $args = join "&", @create_args;

    my $create_url =
        $api_host
      . $nodes_endpoint
      . "/$lowest_node/lxc"
      . "?$args"
      . "&net0=$net0";
    my $create_response =
      $ua->request( POST $create_url,
        @pve_auth_cookie, @csrf_prevention_token );
    if ( $create_response->is_success ) {
        $vmid = $next_id;
        do {
            sleep(15);
            my $status_url =
                $api_host
              . $nodes_endpoint
              . "/$lowest_node/lxc"
              . "/$vmid/status/current";
            my $status_response = $ua->get( $status_url, @pve_auth_cookie );
            if ( $status_response->is_success ) {
                my $content_data =
                  decode_json( $status_response->decoded_content );
                local $name = $content_data->{data}->{name};
                $status = $content_data->{data}->{status};
            }
        } until ( defined $status );
        print "Container $next_id created!\n";
    }
    else {
        print "Create failed.\n";
        print $create_response->request->as_string;
        print $create_response->as_string;
    }
    return;
}

# Delete a container
sub Delete {
    &Access( $user, $password );
    if ( $status ne 'stopped' ) {
        print "This container is running. Would you like to stop it first? ";
        chomp( my $response = <> );
        if ( $response eq 'yes' ) {
            &Stop($vmid);
            do {
                sleep(5);
                &StatusOne($vmid);
            } until ( $status eq 'stopped' );
            my $delete_url =
              $api_host . $nodes_endpoint . "/$node/lxc" . "/$vmid";
            my $delete_response =
              $ua->delete( $delete_url, @pve_auth_cookie,
                @csrf_prevention_token );
            if ( $delete_response->is_success ) {
                print "Container $vmid deleted!\n";
            }
            else {
                print "Delete failed.\n";
                print $delete_response->request->as_string;
                print $delete_response->as_string;
            }
        }
        else {
            print "Can't delete a running container. Aborting.\n";
            exit 1;
        }
    }
    else {
        my $delete_url = $api_host . $nodes_endpoint . "/$node/lxc" . "/$vmid";
        my $delete_response =
          $ua->delete( $delete_url, @pve_auth_cookie, @csrf_prevention_token );
        if ( $delete_response->is_success ) {
            print "Container $vmid deleted!\n";
        }
        else {
            print "Delete failed.\n";
            print $delete_response->request->as_string;
            print $delete_response->as_string;
        }
    }
    return;
}

# Get next available container ID
sub NextID {
    &Access( $user, $password );
    my $cluster_url = $api_host . $cluster_endpoint . "/nextid";
    my $cluster_response = $ua->get( $cluster_url, @pve_auth_cookie );
    if ( $cluster_response->is_success ) {
        my $next_id_data = decode_json( $cluster_response->decoded_content );
        $next_id = $next_id_data->{data};
        print "Next ID is $next_id.\n";
    }
    else {
        print "NextID failed.\n";
        print $cluster_response->request->as_string;
        print $cluster_response->as_string;
    }
    return;
}

# Get next available IP address
sub NextIP {
    &Access( $user, $password );
    my @available_ips;
    my $partial_ip;
    my $complete_ip;

    foreach $partial_ip (@ip_block) {
        $complete_ip = $ip_range . $partial_ip . '/24';
        push( @available_ips, $complete_ip );
    }

    my $nextip_url = $api_host . $cluster_endpoint . "/resources?type=vm";
    my $nextip_response = $ua->get( $nextip_url, @pve_auth_cookie );
    if ( $nextip_response->is_success ) {
        my $content_data = decode_json( $nextip_response->decoded_content );
        foreach my $container ( @{ $content_data->{data} } ) {
            my $container_id = $container->{vmid};
            my $node         = $container->{node};
            my $config_url =
              $api_host . $lxc_endpoint . "/$container_id/config";
            my $config_response = $ua->get( $config_url, @pve_auth_cookie );
            if ( $config_response->is_success ) {
                my $config_content_data =
                  decode_json( $config_response->decoded_content );
                local $net0_string = $config_content_data->{data}->{net0};
                if ( defined $net0_string ) {
                    my %net0 = split /[,=]/, $net0_string;
                    if ( $net0{ip} ~~ @available_ips ) {
                        my $index = 0;
                        $index++ until $available_ips[$index] eq $net0{ip};
                        splice( @available_ips, $index, 1 );
                    }
                }
            }
            else {
                print "Failed to get container config.\n";
                print $config_response->request->as_string;
                print $config_response->as_string;
                exit 0;
            }
        }
        $next_ip = shift @available_ips;
        print "The next available IP is: $next_ip\n";
    }
    else {
        print "Failed to get next IP.\n";
        print $nextip_response->request->as_string;
        print $nextip_response->as_string;
        exit 0;
    }
    return;
}

# Get status of all containers
sub StatusAll {
    &Access( $user, $password );
    my $status_url = $api_host . $cluster_endpoint . "/resources?type=vm";
    my $status_response = $ua->get( $status_url, @pve_auth_cookie );
    if ( $status_response->is_success ) {
        my $content_data = decode_json( $status_response->decoded_content );
        foreach my $container ( @{ $content_data->{data} } ) {
            print $container->{vmid} . ". "
              . $container->{name} . "\t=> "
              . $container->{status} . "\n";
        }
    }
    else {
        print "Failed to get status.\n";
        print $status_response->request->as_string;
        print $status_response->as_string;
        exit 0;
    }
    return;
}

# Get status of given container
sub StatusOne {
    &Access( $user, $password );
    my $status_all = $api_host . $cluster_endpoint . "/resources?type=vm";
    my $status_all_response = $ua->get( $status_all, @pve_auth_cookie );
    if ( $status_all_response->is_success ) {
        my $content_data = decode_json( $status_all_response->decoded_content );
        foreach my $container ( @{ $content_data->{data} } ) {
            if ( $container->{vmid} eq $vmid ) {
                $node = $container->{node};
            }
        }
    }
    my $status_one =
      $api_host . $nodes_endpoint . "/$node/lxc" . "/$vmid/status/current";
    my $status_one_response = $ua->get( $status_one, @pve_auth_cookie );
    if ( $status_one_response->is_success ) {
        my $content_data = decode_json( $status_one_response->decoded_content );
        local $name = $content_data->{data}->{name};
        $status = $content_data->{data}->{status};
        print "$name\t\t=> $status\n";
    }
    else {
        print "Failed to get status for $vmid: ["
          . $status_one_response->status_line() . "]\n";
        print "Listing all containers instead...\n\n";
        &StatusAll();
        exit 1;
    }
    return;
}

# Start given container
sub Start {
    &Access( $user, $password );
    if ( $status eq 'running' ) {
        print "This container is already running!\n";
        exit 1;
    }
    else {
        my $start_url =
          $api_host . $nodes_endpoint . "/$node/lxc" . "/$vmid/status/start";
        my $start_response = $ua->request( POST $start_url,
            @pve_auth_cookie, @csrf_prevention_token );
        if ( $start_response->is_success ) {
            do {
                sleep(5);
                &StatusOne($vmid);
            } until ( $status eq 'running' );
            print "Container $vmid started!\n";
        }
        else {
            print "Start failed.\n";
            print $start_response->request->as_string;
            print $start_response->as_string;
        }
    }
    return;
}

# Stop given container
sub Stop {
    &Access( $user, $password );
    if ( $status eq 'stopped' ) {
        print "This container is already stopped!\n";
        exit 1;
    }
    else {
        my $stop_url =
          $api_host . $nodes_endpoint . "/$node/lxc" . "/$vmid/status/stop";
        my $stop_response = $ua->request( POST $stop_url,
            @pve_auth_cookie, @csrf_prevention_token );
        if ( $stop_response->is_success ) {
            do {
                sleep(5);
                &StatusOne($vmid);
            } until ( $status eq 'stopped' );
            print "Container $vmid stopped!\n";
        }
        else {
            print "Stop failed.\n";
            print $stop_response->request->as_string;
            print $stop_response->as_string;
        }
    }
    return;
}

__END__

=pod

=head1 NAME

proxmox-api - An interactive tool that can interact with the Proxmox 4.x API

A few things you'll need to note before using this:

=item If you're using a self-signed certificate, be sure and uncomment the %ssl_opts hash

=item You'll need to fill in or modify the relevant IP address information: ip_range, ip_block and gw

=item I haven't implemented any functions yet for the pools and storage endpoints

=head1 SYNOPSIS

proxmox-api [options]

Help Options:

  --help      Show help information

  --manual    Show the manual

  --action    Which API action you'd like to perform < Create | Delete | Status | Start | Stop | NextID | NextIP >

=head1 OPTIONS

=over 8

=item B<--help>

=item B<--manual>

=back

=head1 ARGUMENTS

--action < Create | Delete | Status | Start | Stop | NextID | NextIP >

=head1 EXAMPLES

Create a container:
    proxmox-api.pm --action Create

Delete a container:
    proxmox-api.pm --action Delete

Check container status (one or all):
    proxmox-api.pm --action Status
    
Start a container:
    proxmox-api.pm --action Start

Stop a container:
    proxmox-api.pm --action Stop

List the next available container ID:
    proxmox-api.pm --action NextID

List the next available IP address:
    proxmox-api.pm --action NextIP

=head1 DESCRIPTION

This commandline utility allows for interactive, one-off actions against the Proxmox 4.x API.
There must exist in the same directory a proxmox.properties file containing:
    user=user@realm
    password=password

=head1 AUTHOR

Jeff Melton
--
jeff@themeltonplantation.com

=cut
