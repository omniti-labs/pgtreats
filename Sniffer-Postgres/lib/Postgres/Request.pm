package Postgres::Request;

use strict;
use Data::Dumper;

sub log {
  my $self = shift;
  my $class = ref $self || $self;
  my $m = shift;
#  print "$class: $m\n";
}
sub logf {
  my $self = shift;
  my $fmt = shift;
  $self->log(sprintf($fmt, @_));
}

my $types = {
  'B' => { name => 'Bind', parse => sub { ($_[0]->{portal}, $_[0]->{handle}) = unpack("x5Z*Z*", $_[1]); } },
  'E' => { name => 'Execute', parse => sub { ($_[0]->{handle}, $_[0]->{limit}) = unpack("x5Z*N", $_[1]); }, complete => 1 },
  'F' => { name => 'Function Call', complete =>1  },
  'H' => { name => 'Flush' },
  'P' => { name => 'Parse', parse => \&parse_parse, complete => 1 },
  'p' => { name => 'Password Message' },
  'Q' => { name => 'Simple Query', parse => sub { $_[0]->{query} = unpack("x5Z*", $_[1]); }, complete => 1 },
  'C' => { name => 'Close', complete => 1 },
  'S' => { name => 'Sync' },
  'X' => { name => 'Terminate', complete => 1 },
  'D' => { name => 'Describe', parse => sub { ($_[0]->{describing}, $_[0]->{handle}) = unpack("x5cZ*", $_[1]); } },
  'd' => { name => 'Copy Data' },
  'c' => { name => 'Copy Data Completed' },
  'f' => { name => 'Copy Data Failed' },
};

sub is_complete {
  my $self = shift;
  my $t = $types->{$self->{type}};
  return 1 if($t && $t->{complete});
  return 0;
}

sub parse_parse {
  my $self = shift;
  my $buf = shift;
  my ($handle, $query, @args) = unpack("x5 Z*Z* n/N", $buf);
  $self->{handle} = $handle;
  $self->{query} = $query;
  $self->{args} = \@args
}

sub parse {
  my $class = shift;
  my $buf = shift;
  my $self = bless { whence => shift }, $class;

  # special case for cancel query
  if(unpack("N", substr($$buf, 0, 4)) == 16 &&
     unpack("N", substr($$buf, 4, 4)) == 80877102) {
    $self->{type} = 'Cancel';
    $self->{pid} = unpack("N", substr($$buf, 8, 4));
    return $self;
  }

  my $type = substr($$buf, 0, 1);
  my $len = unpack("N", substr($$buf, 1, 4));
  # short-circuit the short packet.
  return undef if(length($$buf) - 1 < $len);

  $self->{type} = $type;
  $self->{len} = $len;

  $self->{query} = '';
  if(exists $types->{$type}) {
    my $t = $types->{$type};
    $class->log("type: " . $t->{name});
    $t->{parse}->($self, $$buf) if($t->{parse});
  }
  else {
    $class->logf("type: '%s'", $self->{type});
  }
  #$class->logf("len: %d", $len);
  #$class->logf("actual len: %d", length($$buf) - 1);
  if($len != (length($$buf) - 1)) {
    substr($$buf, 0, 1 + $len) = '';
  }
  else {
    $$buf = '';
  }
  return $self;
}

sub as_string {
  my $self = shift;
  return $self->{query};
}
1;
