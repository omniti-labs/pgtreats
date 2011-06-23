#!/opt/OMNIperl/bin/perl

use warnings;
use strict;

use lib '/www/CPAN/lib/site_perl/5.8.8';

use DBI;

my $dbh = DBI->connect("dbi:Pg:dbname=postgres;port=54001", 'postgres', '', { AutoCommit => 1 } );

my ($buff_tot) = $dbh->selectrow_array(q[SELECT setting FROM pg_settings WHERE name='shared_buffers']);

$dbh->disconnect();

my $count = 0;

my @header = ('Time', 'Buffers Flushed', 'Log Files Added','Log Files Removed','Log Files Recycled','Write Time','Sync Time','Total Time');

my @sum = (0) x scalar(@header);
my @max = (0) x scalar(@header);
my %rows = ();

while (my $line = <>)
{
    if (my @row = $line =~ m/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \w{3})::\@:\[\d+\]:LOG:  checkpoint complete: wrote (\d+) buffers \(\d+\.\d%\); (\d+) transaction log file\(s\) added, (\d+) removed, (\d+) recycled; write=(\d+.\d{3}) s, sync=(\d+.\d{3}) s, total=(\d+.\d{3}) s/)
    {
        $count++;

        for (my $i = 1; $i < scalar(@row); $i++)
        {
            $sum[$i] += $row[$i];
            if ($row[$i] > $max[$i])
            {
                $max[$i] = $row[$i];
            }
        }

        $rows{$row[0]} = \@row;
    }
}

my @median = @{ $rows{(sort {$rows{$a}[1] <=> $rows{$b}[1]} keys %rows)[(int($count/2))]} };

for (my $i = 1; $i < scalar(@header); $i++)
{
    print "$header[$i] - Max: $max[$i]";
    if ($i == 1)
    {
        print " Pct: " . sprintf("%.3f",$max[$i] / $buff_tot * 100) . "%";
    }
    print " Average: " . sprintf("%.3f",$sum[$i] / $count);
    if ($i == 1)
    {
        print " Pct: " . sprintf("%.3f",($sum[$i] / $count) / $buff_tot * 100) . "%";
    }
    print " Median: " . $median[$i];
    if ($i == 1)
    {
        print " Pct: " . sprintf("%.3f",$median[$i] / $buff_tot * 100) . "%";
    }
    print "\n";
}

my $tt = 0;

foreach my $key (sort {$rows{$b}[1] <=> $rows{$a}[1]} keys %rows)
{
    if ($tt++ >= 10)
    {
        last;
    }
    print "\n";
    for (my $i = 0; $i < scalar(@header); $i++)
    {
        print "$header[$i] - $rows{$key}[$i]";
        if ($i == 1)
        {
            print " Pct: " . sprintf("%.3f",$rows{$key}[$i] / $buff_tot * 100) . "%";
        }
        print"\n";
    }
}
