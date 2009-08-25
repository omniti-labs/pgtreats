#!/usr/bin/env perl
use strict;
use warnings;
use Carp;
use English qw( -no_match_vars );
use Getopt::Long qw(:config no_ignore_case);
use Data::Dumper;
use File::Basename;
use File::Path;
use File::Temp qw( tempdir );
use POSIX qw( strftime );

my $O = get_options();

validate_options();

my $sql = get_report_sql();

run_report( $sql );

send_report_by_mail();

cleanup();

exit;

sub make_path {

    $File::Path::VERSION =~ m{\A(\d+)} or die "File::Path::VERSION doesn't start with digits? : $File::Path::VERSION\n";
    my $ver = $1;
    return $ver < 2 ? File::Path::mkpath( @_ ) : File::Path::make_path( @_ );
}

sub reformat_report {
    my $txt = shift;
    my @rows = split /\r?\n/, $txt;
    return(0, '(0 rows)') if 0 == scalar @rows;

    my $template;
    if ($O->{'format'} eq 'simple') {
        $template = "__[3u]i__. __[-60s]relation__ __[7u]wastedpages__ of __[7u]relpages__ pages wasted (__[.1f]percent__%), __pwastedbytes__ of __prelbytes__.\n";
    } else {
        $template = "-- __[3u]i__. __[-60s]relation__ __[7u]wastedpages__ of __[7u]relpages__ pages wasted (__[.1f]percent__%), __pwastedbytes__ of __prelbytes__.\n";
        if ($O->{'mode'} eq 'tables') {
            $template .= "CLUSTER __relation__; -- You might need to add: USING <some_index_name>\n\n";
        } else {
            $template .= "REINDEX INDEX __relation__;\n\n";
        }
    }

    my $report = '';
    my $i = 0;
    for my $row ( @rows ) {
        $i++;
        my @columns = split /\|/, $row;
        my %data;
        @data{qw( relation reltuples relpages otta bloat wastedpages wastedbytes pwastedbytes relbytes prelbytes )} = @columns;
        $data{ 'percent' } = 100 * $data{'wastedpages'} / $data{'relpages'};
        $data{"i"} = $i;
        my $string = $template;
        $string =~ s#__(?:\[(.*?)\])?([a-z]+)__#sprintf '%'.($1||'s'), $data{$2}||''#ge;
        $report .= $string;
    }
    return( scalar @rows, $report );
}

sub send_report_by_mail {
    return unless $O->{ 'recipients' };
    return if ( !-s 'report.stdout' ) && ( !-s 'report.stderr' );

    my $report = slurp_file( 'report.stdout' );
    my ( $row_count, $reformatted ) = reformat_report( $report );
    if (   ( 0 == $row_count )
        && ( !$O->{ 'send-zero' } ) )
    {
        log_info( 'Report contains 0 rows. Skipping mailing.' );
        return;
    }

    my @recipients = map { my $q = $_; $q =~ s/\A\s*|\s*\z//; $q } split /\s*,\s*/, $O->{ 'recipients' };

    my $subject = strftime( $O->{ 'subject' }, localtime time );
    $subject =~ s/__(.*?)__/defined $O->{ $1 } ? $O->{$1} : ''/ge;

    my @command = ();
    push @command, $O->{ 'mailx' };
    push @command, '-s', $subject;
    push @command, @recipients;

    my $command_string = join ' ', map { quotemeta $_ } @command;
    $command_string .= ' 2>mailx.stderr >mailx.stdout';
    my $mailx;
    unless ( open $mailx, '|-', $command_string ) {
        log_info( 'Cannot open mailx command (%s): %s', $command_string, $OS_ERROR, );
        return;
    }
    if ( -s 'report.stderr' ) {
        print $mailx "STDERR:\n" . slurp_file( 'report.stderr' ) . "\n";
    }
    print $mailx "Report:\n" . $reformatted . "\n";
    close $mailx;

    if ( -s 'mailx.stderr' ) {
        log_info( "mailx STDERR:\n%s", slurp_file( 'mailx.stderr' ) );
    }
    if ( -s 'mailx.stdout' ) {
        log_info( "mailx STDOUT:\n%s", slurp_file( 'mailx.stdout' ) );
    }
    else {
        log_info( 'mailx (%s) finished', $command_string, );
    }
    return;
}

sub cleanup {
    unlink qw( report.sql report.stdout report.stderr mailx.stderr mailx.stdout );
    chdir '/';
    return;
}

sub run_report {
    my $sql = shift;

    open my $fh, '>', 'report.sql' or die 'Cannot write to report.sql file in ' . $O->{ 'workdir' } . ' : ' . $OS_ERROR;
    print $fh $sql;
    close $fh;

    my @command = ();
    push @command, $O->{ 'psql' };
    push @command, '-d', $O->{ 'dbname' } if $O->{ 'dbname' };
    push @command, '-h', $O->{ 'host' } if $O->{ 'host' };
    push @command, '-p', $O->{ 'port' } if $O->{ 'port' };
    push @command, '-U', $O->{ 'user' } if $O->{ 'user' };
    push @command, '-f', 'report.sql';
    push @command, '-qAt' unless $O->{ 'format' } eq 'table';

    my $command_string = join ' ', map { quotemeta $_ } @command;
    $command_string .= ' 2>report.stderr >report.stdout';

    log_info( 'Calling psql: [%s]', $command_string );
    my $status = system $command_string;
    log_info( 'psql finished with status: %d', $status );

    if ( -s 'report.stderr' ) {
        log_info( "STDERR:\n%s", slurp_file( 'report.stderr' ) );
    }
    if ( -s 'report.stdout' ) {
        log_info( "Report:\n%s", slurp_file( 'report.stdout' ) );
    }
    else {
        log_info( 'There is no report!' );
    }
    return;
}

sub slurp_file {
    my $file_name = shift;
    open my $fh, '<', $file_name or die "Cannot open $file_name for reading: $OS_ERROR\n";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub log_info {
    my ( $format, @args ) = @_;
    $format =~ s/\s*\z/\n/;
    my $timestamp = strftime( '%Y-%m-%d %H:%M:%S %z', localtime time );
    printf { $O->{ 'logfh' } } "%s $format", $timestamp, @args;
    return;
}

sub get_report_sql {

    my $sql = get_base_sql();

    my @where_parts = ();

    push @where_parts, 'schemaname ~ ' . sqlify_regexp( $O->{ 'schema' } )                if $O->{ 'schema' };
    push @where_parts, 'schemaname !~ ' . sqlify_regexp( $O->{ 'exclude-schema' } )       if $O->{ 'exclude-schema' };
    push @where_parts, 'tablename ~ ' . sqlify_regexp( $O->{ 'relation-name' } )          if $O->{ 'relation-name' };
    push @where_parts, 'tablename !~ ' . sqlify_regexp( $O->{ 'exclude-relation-name' } ) if $O->{ 'exclude-relation-name' };

    if ( 0 == scalar @where_parts ) {
        $sql =~ s/__EXTRA__WHERE__//g;
        return $sql;
    }
    my $where_string = join ' AND ', @where_parts;
    $sql =~ s/__EXTRA__WHERE__/ WHERE $where_string /g;

    my @pages_where = ();

    push @pages_where, 'relpages >= ' . $O->{ 'min-pages' }           if $O->{ 'min-pages' };
    push @pages_where, 'wastedpages >= ' . $O->{ 'min-wasted-pages' } if $O->{ 'min-wasted-pages' };

    return $sql if 0 == scalar @pages_where;

    $sql = "SELECT * FROM ( $sql ) as subquery WHERE " . join( ' AND ', @pages_where );

    return $sql;
}

sub sqlify_regexp {
    my $regex_string = shift;
    $regex_string =~ s/(['\\])/$1$1/g;
    return "E'$regex_string'";
}

sub get_base_sql {
    if ( 'tables' eq $O->{ 'mode' } ) {
        return q{
SELECT
  schemaname||'.'||tablename as relation, reltuples::bigint, relpages::bigint, otta,
  ROUND(CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS bloat,
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,
  pg_size_pretty((CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END)::bigint) AS pwastedbytes,
  bs*relpages::bigint as relbytes,
  pg_size_pretty((bs*relpages::bigint)::bigint) as prelbytes
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta 
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+count(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::numeric) AS bs,
          CASE WHEN substring(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
__EXTRA__WHERE__
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename and cc.relkind = 'r'
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
) AS sml
WHERE sml.relpages - otta > 128 
      AND ROUND(CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages/otta::numeric END,1) > 1.2 
      AND CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END > 1024 * 100
ORDER BY wastedbytes DESC
        };
    }
    else {
        return q{
SELECT
  schemaname||'.'||iname as relation,ituples::bigint as reltuples, ipages::bigint as relpages, iotta as otta,
  ROUND(CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages/iotta::numeric END,1) AS bloat,
  CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedpages,
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedbytes,
  pg_size_pretty((CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END)::bigint) AS pwastedbytes,
  bs*ipages::bigint as relbytes,
  pg_size_pretty((bs*relpages::bigint)::bigint) as prelbytes
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+count(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::numeric) AS bs,
          CASE WHEN substring(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
__EXTRA__WHERE__
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
WHERE (sml.relpages - otta > 128 OR ipages - iotta > 128) 
  AND ROUND(CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages/iotta::numeric END,1) > 1.2 
  AND CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END > 1024 * 100 
ORDER BY wastedbytes DESC
        };
    }
}

sub get_options {
    my %o = (
        'exclude-schema' => '^(pg_.*|information_schema)$',
        'format'         => 'table',
        'logfile'        => '-',
        'mailx'          => 'mailx',
        'mode'           => 'tables',
        'psql'           => 'psql',
        'send-zero'      => undef,
        'subject'        => '[%Y-%m-%d %H:%M:%S %z] Bloat report for __mode__ in __dbname__ at __host__:__port__',
    );
    show_help_and_die() unless GetOptions(
        \%o,

        # database connection
        'host|h=s',
        'port|p=i',
        'user|U=s',
        'dbname|d=s',

        # object choosing
        'mode|m=s',
        'schema|n=s',
        'exclude-schema|N=s',
        'relation-name|t=s',
        'exclude-relation-name|T=s',
        'min-pages|a=i',
        'min-wasted-pages|A=i',

        # system options
        'logfile|l=s',
        'workdir|w=s',
        'psql|q=s',
        'mailx|x=s',

        # mailing
        'recipients|r=s',
        'subject|s=s',
        'send-zero|z',

        # other
        'format|f=s',
        'help|?',
    );
    show_help_and_die() if $o{ 'help' };
    return \%o;
}

sub validate_options {
    $O->{ 'mode' } = 'tables'  if substr( 'tables',  0, length( $O->{ 'mode' } ) ) eq $O->{ 'mode' };    # make it tables for any prefix of 'tables'
    $O->{ 'mode' } = 'indexes' if substr( 'indexes', 0, length( $O->{ 'mode' } ) ) eq $O->{ 'mode' };    # make it indexes for any prefix of 'indexes'
    show_help_and_die( 'Given mode (%s) is invalid.', $O->{ 'mode' } ) unless $O->{ 'mode' } =~ m{\A(?:tables|indexes)\z};

    for my $regexp_key ( qw( schema exclude-schema relation-name exclude-relation-name ) ) {
        next unless defined $O->{ $regexp_key };
        my $val = $O->{ $regexp_key };
        eval { my $re = qr{$val}; };
        next unless $EVAL_ERROR;
        show_help_and_die( 'Invalid regexp: %s: "%s": %s', $regexp_key, $val, $EVAL_ERROR );
    }

    delete $O->{ 'logfile' } if defined $O->{ 'logfile' } && '-' eq $O->{ 'logfile' };
    if ( defined $O->{ 'logfile' } ) {
        $O->{ 'logfile' } = strftime( $O->{ 'logfile' }, localtime time );
        my $base_dir = dirname( $O->{ 'logfile' } );
        unless ( -d $base_dir ) {
            eval { make_path( $base_dir ); };
            if ( my $error = $EVAL_ERROR ) {
                show_help_and_die( "%s doesn't exist, and cannot be created (via --logfile): %s", $base_dir, $error );
            }
        }
        open my $fh, '>>', $O->{ 'logfile' } or show_help_and_die( 'Cannot write to %s: %s', $O->{ 'logfile' }, $OS_ERROR );
        $O->{ 'logfh' } = $fh;
    }
    else {
        $O->{ 'logfh' } = \*STDOUT;
    }

    if ( defined $O->{ 'workdir' } ) {
        $O->{ 'workdir' } = strftime( $O->{ 'workdir' }, localtime time );
        unless ( -d $O->{ 'workdir' } ) {
            eval { make_path( $O->{ 'workdir' } ); };
            if ( my $error = $EVAL_ERROR ) {
                show_help_and_die( "%s doesn't exist, and cannot be created (via --workdir): %s", $O->{ 'workdir' }, $error );
            }
        }
    }
    else {
        $O->{ 'workdir' } = tempdir( 'CLEANUP' => 1 );
    }

    show_help_and_die( 'psql program name missing!' ) unless $O->{ 'psql' };
    show_help_and_die( 'mailx program name missing!' ) if ( !$O->{ 'mailx' } ) && ( $O->{ 'recipients' } );

    show_help_and_dir( 'Bad format (%s) requsted!', $O->{ 'format' } ) unless $O->{ 'format' } =~ m{\A(?:table|simple|sql)\z};

    chdir $O->{ 'workdir' };
    return;
}

sub show_help_and_die {
    my ( $format, @args ) = @_;
    if ( defined $format ) {
        $format =~ s/\s*\z/\n/;
        printf STDERR $format, @args;
    }
    print STDERR <<_EOH_;
Syntax:
   $PROGRAM_NAME [options]

Options:
  [ database connection ]
   --host                  (-h) : database server host or socket directory
   --port                  (-p) : database server port
   --user                  (-U) : database user name
   --dbname                (-d) : database name to connect to

  [ object choosing ]
   --mode                  (-m) : tables/indexes - show information about which objects.
   --schema                (-n) : regexp to choose which schemas should the report be about
   --exclude-schema        (-N) : regexp to choose which schemas to skip from report
   --relation-name         (-t) : regexp to choose which relations to report on
   --exclude-relation-name (-T) : regexp to choose which relations should be excluded from report
   --min-pages             (-a) : minimal number of pages object have to have to be on report
   --min-wasted-pages      (-A) : minimal number of wasted pages object have to have to be on report

  [ system options ]
   --logfile               (-l) : where to log information about report execution
   --workdir               (-w) : where to create temporary files
   --psql                  (-q) : which psql binary to use
   --mailx                 (-x) : which mailx binary to use

  [ mailing ]
   --recipients            (-r) : comma separated list of emails that will get the report
   --subject               (-s) : subject of the mail to be sent with report
   --send-zero             (-z) : if it is set $PROGRAM_NAME will send email even if there are no bloated relations.

  [ other ]
   --format                (-f) : format of report (table, simple or sql)
   --help                  (-?) : show this help page

Defaults:
   --exclude-schema   '^(pg_.*|information_schema)\$'
   --format           table
   --logfile          -
   --mailx            mailx
   --min-pages        0
   --min-wasted-pages 0
   --mode             tables
   --psql             psql
   --subject          [%Y-%m-%d %H:%M:%S %z] Bloat report for __mode__ in __dbname__ at __host__:__port__

Notes:
    logfile, workdir and subject can contain strftime-styled %marks.
    Additionally subject can will be parsed for __XXX__ strings, and there will be replaced by value of XXX option (full names of options have to be provided).
    $PROGRAM_NAME will try to create necessary directories (logfile and workdir) if they don't exist.
    - as logfile means logging to STDOUT.
_EOH_
    exit 1;
}
