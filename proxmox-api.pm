#!/usr/bin/env perl

# This is an interactive tool that implements a few of the Proxmox 4.x API
# functions. See Usage and inline comments below. There are a number of static
# values assigned that you may wish to change.
#
# While there is another Perl project that seeks to aid interaction with the
# Proxmox API, I found it easier, more instructive, and ultimately more useful
# for my own purposes to build my own tool.
#
# Hashtag YMMV
#
# Usage:
# perl ./proxmox-api.pm --user < user@realm > --password < password > \
#		--action < NextID | NextIP | Create | Delete | Status | Start | Stop >

# Comment the following line if you're using a self-signed cert
use strict;
use warnings;

use Net::IP;
use Net::Ping;
use URI::Escape;
use Getopt::Long;
use Term::ReadKey;
use LWP::UserAgent;
use JSON qw(decode_json);
use HTTP::Request::Common qw(POST);

# Be sure and fill in your Proxmox node's hostname or IP address
my $api_host         = "https://{your host here}:8006/api2/json";
my $access_endpoint  = "/access/ticket";
my $cluster_endpoint = "/cluster";
my $nodes_endpoint   = "/nodes";
my $lxc_endpoint     = $nodes_endpoint . "/pve/lxc";

# I haven't implemented any functions off these endpoints yet, but they're here
# because I might... someday.
#
# my $pools_endpoint   = "/pools";
# my $storage_endpoint = "/storage";

my $user;
my $password;
my $action;
my $hostname;
my $hostpass;
my $vmid;
my $status;

my $usage = <<'END_USAGE';
Usage: $0
Required parameters:
	--user		<user>
	--password	<password>
	--action 	< NextID | NextIP | Create | Delete | Status | Start | Stop >
END_USAGE

GetOptions(
    'user=s'     => \$user,
    'password=s' => \$password,
    'action=s'   => \$action,
) or die "$usage\n";

# Uncomment this block if you're using a self-signed cert
# my %ssl_opts = (
#    ssl_opts => {
#        SSL_verify_mode => SSL_VERIFY_NONE,
#        verify_hostname => 0,
#    },
# );
#
# Also uncomment this, and comment the next
# my $ua = LWP::UserAgent->new(%ssl_opts);
my $ua = LWP::UserAgent->new();

my $pve_auth_cookie;
my @pve_auth_cookie;
my $csrf_prevention_token;
my @csrf_prevention_token;
my $next_id;

# I'm using a static block of IP addresses that are available to our
# containers. Change as needed.
my $ip_range = "xxx.xx.xxx.";
my @ip_block = qw( xxx xxx xxx xxx xxx xxx xxx );
my $next_ip;

# Parse arguments to call action subroutines
# I feel like I need to clean up this section, but it works for now.
if ( $action eq 'NextID' ) {
    &Access( $user, $password );
    &NextID(@pve_auth_cookie);
}
elsif ( $action eq 'NextIP' ) {
    &Access( $user, $password );
    &NextIP();
}
elsif ( $action eq 'Create' ) {
    my $id_chosen = 0;
    do {
        print "Do you know the VM ID you'd like to use? ";
        chomp( my $response = <> );
        if ( $response eq 'no' ) {
            &Access( $user, $password );
            &NextID(@pve_auth_cookie);
            $id_chosen = 1;
        }
        elsif ( $response eq 'yes' ) {
            print "Please enter the ID: ";
            chomp( $vmid = <> );
            if ( length $vmid ne 3 || $vmid lt 100 ) {
                print "You must select a 3-digit ID greater than 100.\n";
            }
            else {
                $next_id   = $vmid;
                $id_chosen = 1;
            }
        }
        else {
            print "Please enter 'yes' or 'no'.\n";
        }
    } until ( $id_chosen == 1 );
    print "Enter the hostname: ";
    chomp( $hostname = <> );
    print "Enter the root password (will not echo): ";
    ReadMode( noecho => STDIN );
    chomp( $hostpass = <> );
    print "\n";
    ReadMode( restore => STDIN );
    &Access( $user, $password );
    &NextIP();
    $vmid = $next_id;
    &Create( $hostname, $hostpass, $next_id, $next_ip, %net0 );
    do {
        sleep(15);
        &StatusOne($vmid);
    } until ( defined $status );
    print "Would you like to start the VM now? ";
    chomp( $response = <> );
    if ( $response eq 'yes' ) {
        &Start($vmid);
    }
    else {
        exit 1;
    }
}
elsif ( $action eq 'Delete' ) {
    print "What container ID would you like to delete? ";
    chomp( $vmid = <> );
    unless ( $vmid =~ /^[0-9]{3}$/ ) {
        print "You must select a 3-digit ID greater than 100.\n";
        print "Listing all containers...\n";
        &Access( $user, $password );
        &StatusAll();
    }
    else {
        &Access( $user, $password );
        &StatusOne($vmid);
        &Delete( $vmid, $status );
    }
}
elsif ( $action eq 'Status' ) {
    my $status_chosen = 0;
    do {
        my $query = <<'END_QUERY';
Do you want to check the status of:
1) one container or,
2) all containers?
END_QUERY
        print $query;
        print "Enter 1 or 2: ";
        chomp( my $response = <> );
        if ( $response == 1 ) {
            print "Which VM? ";
            chomp( $vmid = <> );
            if ( length $vmid ne 3 || $vmid lt 100 ) {
                print "You must select a 3-digit ID greater than 100.\n";
            }
            else {
                &Access( $user, $password );
                &StatusOne($vmid);
                $status_chosen = 1;
            }
        }
        elsif ( $response == 2 ) {
            &Access( $user, $password );
            &StatusAll($vmid);
            $status_chosen = 1;
        }
        else {
            print "Please select either option 1 or 2.\n";
        }
    } until ( $status_chosen == 1 );
}
elsif ( $action eq 'Start' ) {
    print "What container ID would you like to start? ";
    chomp( $vmid = <> );
    if ( length $vmid ne 3 && $vmid lt 100 ) {
        print "You must select a 3-digit ID greater than 100.\n";
    }
    else {
        &Access( $user, $password );
        &StatusOne($vmid);
        &Start( $vmid, $status );
    }
}
elsif ( $action eq 'Stop' ) {
    print "What container ID would you like to stop? ";
    chomp( $vmid = <> );
    if ( length $vmid ne 3 && $vmid lt 100 ) {
        print "You must select a 3-digit ID greater than 100.\n";
    }
    else {
        &Access( $user, $password );
        &StatusOne($vmid);
        &Stop( $vmid, $status );
    }
}

# Get access ticket
sub Access {
    my $access_url =
      $api_host . $access_endpoint . "?username=$user" . "&password=$password";
    my $access_response = $ua->post($access_url);
    if ( $access_response->is_success ) {
        my $content = $access_response->decoded_content;
        my $login_ticket_data =
          decode_json( $access_response->decoded_content );
        my $ticket = $login_ticket_data->{data};
        $pve_auth_cookie       = $ticket->{ticket};
        $csrf_prevention_token = $ticket->{CSRFPreventionToken};
    }
    else {
        print "Access failed.\n";
        my $content = $access_response->decoded_content;
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

# Create a new container
# Again with the static values. Tweak as you see fit.
sub Create {
    my %net0 = (
        bridge => 'vmbr0',
        name   => 'eth0',
        gw     => 'xxx.xxx.xxx.xxx',
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
    # Note that Proxmox requires the IP address in the form "IPv4/CIDR" and
    # that I'm using IPv4 only
    my $ip = ',ip=' . $next_ip . '/24';
    $ip   = uri_escape($ip);
    $net0 = $net0 . $ip;

    my %create_args = (
        vmid     => $next_id,
        hostname => $hostname,

        # We use a SAN in production, but the test environment uses local
        # storage. You may wish to change this value.
        storage  => 'local',
        password => $hostpass,

        # This is a static value that you may wish to change to fit your
        # environment
        ostemplate => 'local:vztmpl/debian-8.0-standard_8.0-1_amd64.tar.gz',
    );
    my @create_args;
    for my $key ( keys %create_args ) {
        push @create_args, join "=", map { uri_escape($_) } $key,
          $create_args{$key};
    }
    local $args = join "&", @create_args;

    my $create_url = $api_host . $lxc_endpoint . "?$args" . "&net0=$net0";
    my $create_response =
      $ua->request( POST $create_url, @pve_auth_cookie,
        @csrf_prevention_token );
    if ( $create_response->is_success ) {
        $vmid = $next_id;
        do {
            sleep(15);
            &StatusOne($vmid);
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
    if ( $status ne 'stopped' ) {
        print "This container is running. Would you like to stop it first? ";
        chomp( my $response = <> );
        if ( $response eq 'yes' ) {
            &Stop($vmid);
            do {
                sleep(5);
                &StatusOne($vmid);
            } until ( $status eq 'stopped' );
            my $delete_url = $api_host . $lxc_endpoint . "/$vmid";
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
        my $delete_url = $api_host . $lxc_endpoint . "/$vmid";
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
    my $cluster_url = $api_host . $cluster_endpoint . "/nextid";
    my $cluster_response = $ua->get( $cluster_url, @pve_auth_cookie );
    if ( $cluster_response->is_success ) {
        my $content      = $cluster_response->decoded_content;
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
    my @available_ips;
    my $complete_ip;

    foreach my $partial_ip (@ip_block) {
        $complete_ip = $ip_range . $partial_ip;
        push( @available_ips, $complete_ip );
    }

    my $nextip_url = $api_host . $lxc_endpoint;
    my $nextip_response = $ua->get( $nextip_url, @pve_auth_cookie );
    if ( $nextip_response->is_success ) {
        my $content      = $nextip_response->decoded_content;
        my $content_data = decode_json( $nextip_response->decoded_content );
        foreach my $container ( @{ $content_data->{data} } ) {
            my $container_id = $container->{vmid};
            my $config_url =
              $api_host . $lxc_endpoint . "/$container_id/config";
            my $config_response = $ua->get( $config_url, @pve_auth_cookie );
            if ( $config_response->is_success ) {
                my $config_content = $config_response->decoded_content;
                my $config_content_data =
                  decode_json( $config_response->decoded_content );
                local $net0_string = $config_content_data->{data}->{net0};
                my %net0 = split /[,=]/, $net0_string;
                if ( grep { $_ eq $net0{ip} } @available_ips ) {
                    shift @available_ips;
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
    my $status_url = $api_host . $lxc_endpoint;
    my $status_response = $ua->get( $status_url, @pve_auth_cookie );
    if ( $status_response->is_success ) {
        my $content      = $status_response->decoded_content;
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
    my $status_url = $api_host . $lxc_endpoint . "/$vmid/status/current";
    my $status_response = $ua->get( $status_url, @pve_auth_cookie );
    if ( $status_response->is_success ) {
        my $content      = $status_response->decoded_content;
        my $content_data = decode_json( $status_response->decoded_content );
        local $name = $content_data->{data}->{name};
        $status = $content_data->{data}->{status};
        print "$name\t\t=> $status\n";
    }
    else {
        print "Failed to get status for $vmid: ["
          . $status_response->status_line() . "]\n";
        print "Listing all containers instead...\n\n";
        &StatusAll();
        exit 1;
    }
    return;
}

# Start given container
sub Start {
    if ( $status eq 'running' ) {
        print "This container is already running!\n";
        exit 1;
    }
    else {
        my $start_url      = $api_host . $lxc_endpoint . "/$vmid/status/start";
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
    if ( $status eq 'stopped' ) {
        print "This container is already stopped!\n";
        exit 1;
    }
    else {
        my $stop_url      = $api_host . $lxc_endpoint . "/$vmid/status/stop";
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

