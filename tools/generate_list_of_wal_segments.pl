#!/usr/bin/perl -w
use strict;

my ( $from_file, $to_file ) = @ARGV;

die 'Bad range.' if $from_file gt $to_file;

my @from = map { hex $_ } $from_file =~ m{(.{8})(.{8})(.{8})};

while (1) {
    print "$from_file\n" unless $from_file =~ m{FF\z};
    last if $from_file eq $to_file;
    $from[2]++;
    if ($from[2] == 256) {
        $from[2] = 0;
        $from[1]++;
    }
    $from_file = sprintf '%08X%08X%08X', @from;
}

exit;
