package Sniffer::Postgres;
use strict;
use Sniffer::Connection::Postgres;
use base 'Class::Accessor::Faster';
use Data::Dumper;
use NetPacket::Ethernet;
use NetPacket::IP;
use NetPacket::TCP;
use Net::Pcap; # just for the convenience function below
use Net::Pcap::FindDevice;
use Carp qw(croak);

use vars qw($VERSION);
my $save;

$VERSION = '0.0.1';

=head1 NAME

Sniffer::Postgres - multi-connection sniffer driver

=head1 SYNOPSIS

  use Sniffer::Postgres;
  my $VERBOSE = 0;

  my $sniffer = Sniffer::Postgres->new(
    callbacks => {
      response => sub { my ($res,$pg) = @_; },
      log      => sub { print $_[0] if $VERBOSE },
      tcp_log  => sub { print $_[0] if $VERBOSE > 1 },
    },
    timeout => 5*60, # seconds after which a connection is considered stale
    stale_connection
      => sub { my ($s,$conn,$key);
               $s->log->("Connection $key is stale.");
               $s->remove_connection($key);
             },
  );

  $sniffer->run(); # uses the "best" default device

  # Or, if you want to feed it the packets yourself:

  while (1) {

    # retrieve ethernet packet into $eth,
    # for example via Net::Pcap
    my $eth = sniff_ethernet_packet;

    # And handle the packet. Callbacks will be invoked as soon
    # as complete data is available
    $sniffer->handle_eth_packet($eth);
  }

This driver gives you callbacks with the completely accumulated
L<Postgres::Request>s or L<Postgres::Response>s as sniffed from the
TCP traffic. You need to feed it the Ethernet, IP or TCP packets
either from a dump file or from L<Net::Pcap> by unpacking them via
L<NetPacket>.

As the whole response data is accumulated in memory you should
be aware of memory issues. If you want to write stuff
directly to disk, you will need to submit patches to L<Sniffer::Connection::Postgres>.

=head1 METHODS

=head2 C<< new %ARGS >>

Creates a new object for handling many Postgres requests.
You can pass in the following arguments:

  connections      - preexisting connections (optional)
  callbacks        - callbacks for the new connections (hash reference)
  timeout          - timeout in seconds after which a connection is considered stale
  stale_connection - callback for stale connections
  inflight         - a destination port to for which in-flight TCP sessions.

=cut

__PACKAGE__->mk_accessors(qw(inflight connections callbacks timeout pcap_device stale_connection last_sweep));

sub new {
  my ($class,%args) = @_;

  $args{connections} ||= {};
  $args{callbacks}   ||= {};
  $args{callbacks}->{log}   ||= sub {};
  $args{stale_connection} ||= sub {
    my ($s,$conn,$key) = @_;
    $conn->log->("$key is stale.");
    $s->remove_connection($key);
  };

  $args{timeout} = 300
    unless exists $args{timeout};

  my $self = $class->SUPER::new(\%args);

  my $user_closed = delete $args{callbacks}->{closed};
  $args{callbacks}->{closed} = sub {
    my $key = $_[0]->flow;
    if (! exists $args{connections}->{$key}) {
      warn "Error: flow() ne connection-key!";
      $key = join ":", reverse split /:/, $key;
    }
    $_[0]->{log}->("Removing $key");
    $self->remove_connection($key);
    goto &$user_closed
      if $user_closed;
  };
  $self->last_sweep(0);
  $self;
}

=head2 C<< $sniffer->remove_connection KEY >>

Removes a connection (or a key) from the list
of connections. This will not have the intended
effect if the connection is still alive, as it
will be recreated as soon as the next packet
for it is received.

=cut

sub remove_connection {
  my ($self,$key) = @_;
  if (ref $key) {
    my $real_key = $key->flow;
    if (! exists $self->connections->{$real_key}) {
      warn "Error: flow() ne connection-key!";
      $real_key = join ":", reverse split /:/, $real_key;
    }
    $key = $real_key;
  }
  delete $self->connections->{$key};
}

=head2 C<< $sniffer->find_or_create_connection TCP, %ARGS >>

This parses a TCP packet and creates the TCP connection
to keep track of the packet order and resent packets.

=cut

sub find_or_create_connection {
  my ($self,$tcp) = @_;

  my $connections = $self->connections;

  # Implement find_or_create() for connections in
  # the base class ...
  my $key = $tcp->{src_port} . ":" . $tcp->{dest_port};
  if (! exists $connections->{$key}) {
    my $key2 = $tcp->{dest_port} . ":" . $tcp->{src_port};
    if (! exists $connections->{$key2}) {
      $self->callbacks->{log}->("Creating connection $key, sequence start at " . $tcp->{seqnum});
      my $c = $self->callbacks;
      my $o = Sniffer::Connection::Postgres->new(
        %$c,
        tcp            => $tcp,
      );
      $connections->{$key} = $o;
    } else {
      $key = $key2
    }
  }

  return $connections->{$key};
}

=head2 C<< $sniffer->stale_connections( TIMEOUT, TIMESTAMP, HANDLER ) >>

Will call the handler HANDLER for all connections that
have a C<last_activity> before TIMESTAMP - TIMEOUT.

All parameters are optional and default to:

  TIMEOUT   - $sniffer->timeout
  TIMESTAMP - time()
  HANDLER   - $sniffer->stale_connection

It returns all stale connections.

=cut

sub stale_connections {
  my ($self,$timeout,$timestamp,$handler) = @_;
  $timeout   ||= $self->timeout;
  $handler   ||= $self->stale_connection;
  $timestamp ||= time();

  my $cutoff = $timestamp - $timeout;

  my $connections = $self->connections;
  my @stale = ();

  if($self->last_sweep < $cutoff) {
    @stale = grep { $connections->{$_}->last_activity < $cutoff } keys %$connections;
    for my $connection (@stale) {
      $handler->($self, $connections->{$connection}, $connection);
    }
    $self->last_sweep($timestamp);
  }

  map {$connections->{$_}} @stale;
}

=head2 C<< $sniffer->live_connections TIMEOUT, TIMESTAMP >>

Returns all live connections. No callback
mechanism is provided here.

The defaults are
  TIMEOUT   - $sniffer->timeout
  TIMESTAMP - time()

=cut

sub live_connections {
  my ($self,$timeout,$timestamp) = @_;
  $timeout   ||= $self->timeout;
  $timestamp ||= time();

  my $cutoff = $timestamp - $timeout;

  my $connections = $self->connections;
  grep { $_->last_activity >= $cutoff } values %$connections;
}

=head2 C<< $sniffer->handle_eth_packet ETH [, TIMESTAMP] >>

Processes a raw ethernet packet. L<Net::PCap> will return
this kind of packet for most Ethernet network cards.

You need to call this method (or one of the other protocol
methods) for every packet you wish to handle.

The optional TIMESTAMP corresponds to the epoch time
the packet was captured at. It defaults to the value
of C<time()>.

=cut

sub handle_eth_packet {
  my ($self,$eth,$ts) = @_;
  $ts ||= time();
  #warn Dumper( NetPacket::Ethernet->decode($eth) );
  $self->handle_ip_packet(NetPacket::Ethernet->decode($eth)->{data}, $ts);
}

=head2 C<< $sniffer->handle_ip_packet IP [, TIMESTAMP] >>

Processes a raw ip packet.

The optional TIMESTAMP corresponds to the epoch time
the packet was captured at. It defaults to the value
of C<time()>.

=cut

sub handle_ip_packet {
  my ($self,$ip,$ts) = @_;
  $ts ||= time();
  #warn Dumper( NetPacket::IP->decode($ip) );
  # This is a workaround around a bug in NetPacket::IP v0.04, which sets the
  # payload to include the trailer
  my $i = NetPacket::IP->decode($ip);

  # Safeguard against malformed IP headers
  $i->{hlen} = 5
      if $i->{hlen} < 5;
  my $conn = $self->handle_tcp_packet(substr($i->{data}, 0, $i->{len}-($i->{hlen}*4)), $ts);
  unless($conn->tcp_connection->dest_host) {
    $conn->tcp_connection->dest_host($i->{dest_ip});
    $conn->tcp_connection->src_host($i->{src_ip});
  }
  $conn;
}

=head2 C<< $sniffer->handle_tcp_packet TCP [, TIMESTAMP] >>

Processes a raw tcp packet. This processes the packet
by handing it off to the L<Sniffer::Connection> which handles
the reordering of TCP packets.

It returns the L<Sniffer::Connection::Postgres> object that
handled the packet.

The optional TIMESTAMP corresponds to the epoch time
the packet was captured at. It defaults to the value
of C<time()>.

=cut

sub handle_tcp_packet {
  my ($self,$tcp,$ts) = @_;
  $ts ||= time();
  if (! ref $tcp) {
    $tcp = NetPacket::TCP->decode($tcp);
  }
  my $conn = $self->find_or_create_connection($tcp);

  # This hacks mid-stream sessions
  if(not defined $conn->tcp_connection->status) {
    if(defined $self->inflight && $tcp->{dest_port} == $self->inflight) {
      $conn->tcp_connection->init_from_packet($tcp);
      $conn->tcp_connection->status('ACK');
    }
  }

  $conn->handle_packet($tcp,$ts);
  # Handle callbacks for detection of stale connections
  $self->stale_connections(undef,$ts);

  # Return the connection that the packet belongs to
  $conn;
}

=head2 C<< run DEVICE, PCAP_FILTER, %OPTIONS >>

Listens on the given device for all TCP
traffic from and to port 80 and invokes the callbacks
as necessary. If you want finer control
over what C<Net::Pcap> does, you need to set up
Net::Pcap yourself.

The C<DEVICE> parameter is used to determine
the device via C<find_device> from L<Net::Pcap::FindDevice>.

The C<%OPTIONS> can be the following options:

  capture_file - filename to which the whole capture stream is
                 written, in L<Net::Pcap> format. This is mostly
                 useful for remote debugging of a problematic
                 sequence of connections.

=cut

sub run {
  my ($self,$device_name,$pcap_filter,%options) = @_;

  my $device = find_device($device_name);
  $pcap_filter ||= "tcp port 5432";

  my $err;
  my ($address, $netmask);
  if (Net::Pcap::lookupnet($device, \$address, \$netmask, \$err)) {
    die 'Unable to look up device information for ', $device, ' - ', $err;
  }
  warn $err if $err;

  #   Create packet capture object on device
  my $pcap = Net::Pcap::open_live($device, 128000, -1, 500, \$err);
  unless (defined $pcap) {
    die "Unable to create packet capture on device '$device' - $err";
  }

  $self->pcap_device($pcap);

  my $filter;
  Net::Pcap::compile(
    $pcap,
    \$filter,
    $pcap_filter,
    0,
    $netmask
  ) && die 'Unable to compile packet capture filter';
  Net::Pcap::setfilter($pcap,$filter);

  if ($options{capture_file}) {
    $save = Net::Pcap::dump_open($pcap,$options{capture_file});
    END {
      # Emergency cleanup
      if ($save) {
        Net::Pcap::dump_flush($save);
        Net::Pcap::dump_close($save);
        undef $save;
      }
    }
  }

  Net::Pcap::loop($pcap, -1, sub {
    if ($save) {
      Net::Pcap::dump($save, @_[1,2]);
    }
    $self->handle_eth_packet($_[2], $_[1]->{tv_sec} + $_[1]->{tv_usec} / 1000000.0 );
  }, '')
    || die 'Unable to perform packet capture';

  if ($save) {
    Net::Pcap::dump_flush($save);
    Net::Pcap::dump_close($save);
    undef $save;
  }
}

=head2 C<< run_file FILENAME, PCAP_FILTER >>

"Listens" to the packets dumped into
a file. This is convenient to use if you
have packet captures from a remote machine
or want to test new protocol sniffers.

The file is presumed to contain an ethernet
stream of packets.

=cut

sub run_file {
  my ($self, $filename, $pcap_filter) = @_;

  $pcap_filter ||= "tcp port 5432";

  my $err;

  my $pcap = Net::Pcap::open_offline($filename, \$err);
  unless (defined $pcap) {
    croak "Unable to create packet capture from filename '$filename': $err";
  }
  $self->pcap_device($pcap);

  my $filter;
  Net::Pcap::compile(
    $pcap,
    \$filter,
    $pcap_filter,
    0,
    0,
  ) && die 'Unable to compile packet capture filter';
  Net::Pcap::setfilter($pcap,$filter);

  #Net::Pcap::loop($pcap, -1, sub { $self->handle_eth_packet($_[2]) }, '');
  Net::Pcap::loop($pcap, -1, sub { $self->handle_eth_packet($_[2], $_[1]->{tv_sec} + $_[1]->{tv_usec} / 1000000.0) }, '')
}

1;

=head1 CALLBACKS

=head2 C<< request REQ, CONN >>

The C<request> callback is called with the parsed request and the connection
object. The request will be an instance of [cpan://Postgres::Request] and will
have an absolute URI if possible. Currently, the hostname for the absolute URI
is constructed from the C<Host:> header.

=head2 C<< response RES, REQ, CONN >>

The C<response> callback is called with the parsed response, the request
and the connection object.

=head2 C<< log MESSAGE >>

The C<log> callback is called whenever the connection makes progress
and in other various situations.

=head2 C<< tcp_log MESSAGE >>

The C<tcp_log> callback is passed on to the underlying C<Sniffer::Connection>
object and can be used to monitor the TCP connection.

=head2 C<< stale_connection SNIFFER, CONN >>

Is called whenever a connection goes over the C<timeout> limit
without any activity. The default handler weeds out stale
connections with the following code:

  sub {
    my ($self,$conn,$key);
    $self->log->("Connection $key is stale.");
    delete $self->connections->{ $key }
  }

=head1 EXAMPLE PCAP FILTERS

Here are some example Net::Pcap filters for common things:

Capture all Postgres traffic between your machine and C<db.example.com>:

     (dest db.example.com && (tcp port 5432))
  || (src  db.example.com && (tcp port 5432))

Capture all Postgres traffic between your machine
and C<db1.example.com> or C<db2.example.com>:

    (dest db1.example.com && (tcp port 5432))
  ||(src db1.example.com  && (tcp port 5432))
  ||(dest db2.example.com && (tcp port 5432))
  ||(src db2.example.com  && (tcp port 5432))

Note that Net::Pcap resolves the IP addresses before using them, so you might
actually get more data than you asked for.

=head1 BUGS

=head1 AUTHOR

Theo Schlossnagle (jesus@omniti.com)

=head1 COPYRIGHT

Copyright (C) 2005 Max Maischein.  All Rights Reserved.
Copyright (C) 2010 OmniTI Computer Consulting, Inc.  All Rights Reserved.

This code is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
