package Sniffer::Connection::Postgres;
use strict;
use Sniffer::Connection;
use Postgres::Request;
use Postgres::Response;

=head1 NAME

Sniffer::Connection::Postgres - Callbacks for a Postgres connection

=head1 SYNOPSIS

You shouldn't use this directly but via L<Sniffer::Postgres>
which encapsulates most of this.

  my $sniffer = Sniffer::Connection::Postgres->new(
    callbacks => {
      response => sub { my ($res,$pg) = @_; },
    }
  );

=cut

use base 'Class::Accessor::Fast';

use vars qw($VERSION);

$VERSION = '0.0.1';

my @callbacks = qw(request response closed log operation);
__PACKAGE__->mk_accessors(qw(tcp_connection sent_buffer recv_buffer _response responses _request requests handles),
                          @callbacks);

sub new {
  my ($class,%args) = @_;

  my $packet = delete $args{tcp};

  # Set up dummy callbacks as the default
  for (@callbacks) { $args{$_} ||= sub {}; };

  for (qw(sent_buffer recv_buffer)) {
    $args{$_} ||= \(my $buffer);
  };

  my $tcp_log = delete $args{tcp_log} || sub {};

  my $self = $class->SUPER::new(\%args);
  $self->tcp_connection(Sniffer::Connection->new(
    tcp           => $packet,
    sent_data     => sub { $self->sent_data(@_) },
    received_data => sub { $self->received_data(@_) },
    closed        => sub {},
    teardown      => sub { $self->closed->($self) },
    log           => $tcp_log,
  ));

  $self->requests([]);
  $self->responses([]);
  $self->handles({});
  $self;
};

sub sent_data {
  my ($self,$data,$conn) = @_;
  $self->flush_received;
  ${$self->{sent_buffer}} .= $data;
  $self->flush_sent($conn);
};

sub received_data {
  my ($self,$data,$conn) = @_;
  $self->flush_sent;
  ${$self->{recv_buffer}} .= $data;
  #warn $data;
  $self->flush_received($conn);
};

sub complete_op {
  my ($pg, $res) = @_;
  return unless ref $res eq 'ARRAY'; # we want only completion events
  my $reqs = $pg->requests();
  return if(scalar(@$reqs) == 0);
  my @queued_reqs = ();
  my $handle = '';
  my $pquery = '';
  while(my $req = shift @$reqs) {
    push @queued_reqs, $req;
    $handle ||= $req->{handle};
    $pquery ||= $pg->handles()->{$handle}->{query}
      if $handle && $pg->handles()->{$handle};
    last if $req->is_complete;
  }
  $queued_reqs[-1]->{query} ||= $pquery;

  my $query_time = $res->[-1]->{whence} - $queued_reqs[-1]->{whence};
  my $query = ($queued_reqs[-1]->{type} eq 'P') ? '(preparing) ' : '';;
  $query .= $queued_reqs[-1]->{query};
  my $results = grep { $_->{type} eq 'D' } @$res;

  if ($query =~ /^DEALLOCATE (\S+)/) {
    delete $pg->handles()->{$1};
  }

  $pg->operation->( {
    wire_requests => \@queued_reqs,
    wire_responses => $res,
    query_time => $query_time,
    query => $query,
    tuples => $results,
    start_time => $queued_reqs[0]->{whence},
    end_time => $res->[-1]->{whence},
    connection => $pg->tcp_connection,
  } );
}

sub flush_received {
  my ($self, $conn) = @_;
  my $buffer = $self->recv_buffer;
  if (scalar(@{$self->requests}) == 0) {
    $$buffer = '';
    return;
  }
  while ($$buffer) {
    if (! (my $res = $self->_response)) {
      # We need to find something that looks like a valid Postgres request in our stream
      $res = Postgres::Response->parse($buffer, $conn ? $conn->last_activity : undef);
      return if not defined($res);
      $self->_response($res);
    };

    my $res = $self->_response;
    $self->response->($res,$self);
    my $responses = $self->responses();
    push @$responses, $res;
    $self->response->($res,$self);
    if($res->is_complete) {
      $self->complete_op($responses);
      $self->responses([]);
    }
    
    $self->_response(undef);
  };
};

sub flush_sent {
  my ($self, $conn) = @_;
  return unless $conn;
  my $buffer = $self->sent_buffer;
  while ($$buffer) {
    if (! (my $req = $self->_request)) {
      $req = Postgres::Request->parse($buffer, $conn->last_activity);
      return if not defined($req);
      $self->_request($req);
    };

    my $req = $self->_request;
    $self->request->($req,$self);
    my $reqs = $self->requests();
    $self->handles()->{$req->{handle}} = $req if($req->{handle} && $req->{query});
    push @$reqs, $req;
    $self->_request(undef);
  };
};

# Delegate some methods
sub handle_packet { my $self = shift;$self->tcp_connection->handle_packet(@_); };
sub flow { my $self = shift; return $self->tcp_connection->flow(@_);};
sub last_activity { my $self = shift; $self->tcp_connection->last_activity(@_) }

1;

=head1 BUGS

=head1 AUTHOR

Theo Schlossnagle (jesus@omniti.com)

=head1 COPYRIGHT

Copyright (C) 2005 Max Maischein.  All Rights Reserved.
Copyright (C) 2010 OmniTI.  All Rights Reserved.

This code is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
