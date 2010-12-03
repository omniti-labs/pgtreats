#!/usr/bin/perl
use strict;
use warnings;
use Carp;
use English qw( -no_match_vars );
use Digest::MD5;

die "You have to provide filenames to calculate md5sum of.\n" if 0 == scalar @ARGV;

for my $filename ( @ARGV ) {
    if ( open my $fh, '<', $filename ) {
        my $md5 = Digest::MD5->new();
        $md5->addfile( $fh );
        printf "%-32s  %s\n", $md5->hexdigest, $filename;
        close $fh;
    }
    else {
        carp "Cannot open $filename for reading: $OS_ERROR\n";
    }
}

exit;

