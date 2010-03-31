package Postgres::Response;

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
  'K' => { name => 'Cancel Key' },
  'B' => { name => 'Bind Complete', complete => 0 },
  '3' => { name => 'Close Complete', complete => 0 },
  'C' => { name => 'Command Complete', parse => sub { $_[0]->{result} = unpack("x5Z*", $_[1]); }, complete => 0 },
  'd' => { name => 'Copy', complete => 0 },
  'c' => { name => 'Copy Complete', complete => 0 },
  'G' => { name => 'Copy In Started' },
  'H' => { name => 'Copy Out Started' },
  'D' => { name => 'Data Row' },
  'I' => { name => 'Empty' },
  'E' => { name => 'Error' },
  'V' => { name => 'Function Call' },
  'n' => { name => 'No Data' },
  'N' => { name => 'Notice' },
  'A' => { name => 'Notification Response' },
  't' => { name => 'Parameter Description' },
  'S' => { name => 'Parameter Status' },
  '1' => { name => 'Parse Complete', complete => 0 },
  's' => { name => 'Portal Suspend' },
  'Z' => { name => 'Ready', complete => 1 },
  'T' => { name => 'Row Description' },
};

sub is_complete {
  my $self = shift;
  my $t = $types->{$self->{type}};
  return 1 if($t && $t->{complete});
  return 0;
}
sub parse {
  my $class = shift;
  my $buf = shift;
  my $self = bless { whence => shift }, $class;

  # Gotta start somewhere
  return undef if (length($$buf) < 5);

  my $type = substr($$buf, 0, 1);
  my $len = unpack("N", substr($$buf, 1, 4));

  # short-circuit the short packet.
  if(length($$buf) - 1 < $len) {
    $self->logf("short packet... (type $type: $len)");
    return undef;
  }

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
  $class->logf("len: %d", $len);
  $class->logf("actual len: %d", length($$buf) - 1);
  if($len < (length($$buf) - 1)) {
    substr($$buf, 0, 1 + $len) = '';
  }
  else {
    $$buf = '';
  }
#  print Dumper($self);
  return $self;
}

1;
