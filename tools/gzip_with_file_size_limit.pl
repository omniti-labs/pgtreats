#!/usr/bin/perl
use strict;
use warnings;
use Carp;
use English qw( -no_match_vars );
use Data::Dumper;
use Getopt::Long;
use IO::Handle;

$OUTPUT_AUTOFLUSH = 1;

my $CFG        = get_config();
my $read_lines = 0;
my $fh_data    = {};

while ( my $line = <STDIN> ) {
    $read_lines++;
    write_line_to_gzip( $line );
    print "\rLine $read_lines processed. : " . $fh_data->{ 'current_position' } . "               " if $CFG->{ 'verbose' };
}
print "\n" if $CFG->{ 'verbose' };

exit;

sub write_line_to_gzip {
    my $line = shift;

    my $fh = get_fh();
    print $fh $line;
    $fh->flush();
    $fh_data->{ 'current_position' } = ( stat( $fh_data->{ 'file_name' } ) )[ 7 ];
    $fh_data->{ 'current_position' } = 0 unless defined $fh_data->{ 'current_position' };
    return;
}

sub create_new_output_handle {
    my $file_name = get_output_file_name();

    open my $fh, '|-', 'gzip -c - > ' . quotemeta( $file_name ) or croak( "Cannot write to $file_name : $OS_ERROR\n" );
    print "Created file: $file_name\n" if $CFG->{ 'verbose' };

    $fh_data->{ 'fh' }               = $fh;
    $fh_data->{ 'current_position' } = 0;
    $fh_data->{ 'file_name' }        = $file_name;

    return $fh;
}

sub get_fh {
    unless ( $fh_data->{ 'fh' } ) {
        $fh_data->{ 'current' } = 1;
        return create_new_output_handle();
    }

    my $total_output_size              = ( $fh_data->{ 'current' } - 1 ) * $CFG->{ 'limit' } + $fh_data->{ 'current_position' };
    my $average_compressed_record_size = $total_output_size / $read_lines;

    if ( $fh_data->{ 'current_position' } + 2 * $average_compressed_record_size > $CFG->{ 'limit' } ) {
        print "\n" if $CFG->{ 'verbose' };
        close $fh_data->{ 'fh' };
        $fh_data->{ 'current' }++;
        return create_new_output_handle();
    }

    return $fh_data->{ 'fh' };
}

sub get_output_file_name {
    return sprintf '%s.%0' . $CFG->{ 'width' } . 'u.gz', $CFG->{ 'filename' }, $fh_data->{ 'current' };
}

sub get_config {
    my %cfg = ();
    unless ( GetOptions( \%cfg, 'limit=i', 'verbose', 'help|?', 'filename=s', 'width=i' ) ) {
        show_help_and_die();
    }
    show_help_and_die() if $cfg{ 'help' };

    show_help_and_die( "Limit is too small, it has to be at least 5MB.\n" ) if 5 > $cfg{ 'limit' };
    show_help_and_die( "Limit is too big, it has to be 500MB at most.\n" )  if 500 < $cfg{ 'limit' };

    show_help_and_die( "Width is too small, it has to be at least 1.\n" ) if 1 > $cfg{ 'width' };
    show_help_and_die( "Width is too big, it has to be 10 at most.\n" )   if 10 < $cfg{ 'width' };

    $cfg{ 'limit' } *= 1024 * 1024;    # Convert megabytes to bytes

    return \%cfg;
}

sub show_help_and_die {
    my @args = @_;
    if ( 0 < scalar @args ) {
        printf STDERR @args;
    }
    print STDERR <<_END_OF_HELP_;
Syntax:
    $PROGRAM_NAME -l 50 -f output -v -w 3

Options:
    --filename (-f)     - Prefix of filename to be saved
    --limit    (-l)     - How many megabytes is the limit for output
    --width    (-w)     - How many characters should part number be padded to
    --verbose  (-v)     - Show verbose information, including progress
    --help     (-?)     - Show this help page

Example:
    cat some_file | $PROGRAM_NAME -l 50 -f output -w 3

Will compress data from some_file, outputting gzipped content to files named:
 - output.001.gz
 - output.002.gz
 - output.003.gz
and so on, trying to keep every file below 50 megabytes.

It can fail at keeping the file under limit in some cases, but generally
even if it will not be able to keep it under 50MB, eventual overhead
should be minimal (up to 1 record (line) from source data).

_END_OF_HELP_
    exit( 1 );
}
