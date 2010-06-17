#!/usr/bin/perl -w
use strict;

my $program = OmniTI::Log_Audit_Information->new();
$program->run();

exit;

package OmniTI::Log_Audit_Information;
use strict;
use Getopt::Long;
use File::Spec;
use English qw( -no_match_vars );
use Carp;
use File::Path;
use File::Basename;
use POSIX qw( strftime );

sub new {
    my $self = bless {}, shift;
    return $self;
}

sub run {
    my $self = shift;
    $self->read_command_line_arguments();

    $self->{ 'time' } = time();
    $self->{ 'time_str' } = strftime( '%Y-%m-%d %H:%M:%S', localtime $self->{ 'time' } );

    $self->get_list_of_dbs();

    $self->get_cluster_wide_data();

    $self->get_database_data( $_ ) for @{ $self->{ 'dbs' } };
    return;
}

sub get_database_data {
    my $self     = shift;
    my $database = shift;

    for my $view ( qw( pg_stat_all_indexes pg_stat_all_tables pg_statio_all_indexes pg_statio_all_tables ) ) {
        $self->print_time_prefixed(
            $database . '-' . $view,
            $self->call_sql( 'copy ( select * from ' . $view . ' ) to stdout', $database )
        );
    }
    return;
}

sub get_cluster_wide_data {
    my $self = shift;

    $self->print_time_prefixed(
        'databases',
        $self->call_sql( 'copy ( select * from pg_stat_database ) to stdout' )
    );
    return;
}

sub print_time_prefixed {
    my $self = shift;
    my ( $type, @output ) = @_;
    my $fh = $self->get_output_writer( $type );
    for my $line ( @output ) {
        printf $fh "%s\t%s", $self->{ 'time_str' }, $line;
    }
    close $fh;
    return;
}

sub get_list_of_dbs {
    my $self = shift;

    my @output = $self->call_sql( 'SELECT datname FROM pg_database WHERE datallowconn ORDER BY 1' );

    chomp for @output;

    $self->{ 'dbs' } = \@output;
    return;
}

sub call_sql {
    my $self     = shift;
    my $sql      = shift;
    my $database = shift;

    my @psql_command = ( $self->{ 'psql-path' } );
    push @psql_command, '-qAtX';
    push @psql_command, ( '-U', $self->{ 'username' } ) if $self->{ 'username' };
    push @psql_command, ( '-h', $self->{ 'host' } )     if $self->{ 'host' };
    push @psql_command, ( '-p', $self->{ 'port' } )     if $self->{ 'port' };
    push @psql_command, ( '-d', $database || $self->{ 'dbname' } );

    push @psql_command, ( '-c', $sql );

    my $psql_str = join ' ', map { quotemeta $_ } @psql_command;

    open my $psql, '-|', $psql_str or croak( "Cannot run psql >$psql_str< : $OS_ERROR.\n" );
    my @output = <$psql>;
    close $psql;

    croak( "Calling psql >$psql_str< failed. CHILD_ERROR=$CHILD_ERROR.\n" ) if $CHILD_ERROR;

    return @output;
}

sub get_output_writer {
    my $self = shift;

    my $type = shift;

    my $output_filename = strftime(
        File::Spec->catfile( $self->{ 'log-path' }, '%Y/%m/db-audit-' . $type . '-%Y-%m-%d_%H00-%H59.log.gz' ),

        localtime $self->{ 'time' },
    );

    my $output_dir = dirname( $output_filename );
    mkpath( [ $output_dir ], 0, oct( "755" ) );

    my $gzip_command = sprintf '%s -c - >> %s', quotemeta( $self->{ 'gzip-path' } ), quotemeta( $output_filename );

    open my $fh, '|-', $gzip_command or croak( "Cannot open gzip writer >$gzip_command< : $OS_ERROR.\n" );
    return $fh;
}

sub read_command_line_arguments {
    my $self = shift;
    my $vars = {
        'log-path'  => '.',
        'gzip-path' => 'gzip',
        'psql-path' => 'psql',
        'dbname'    => 'postgres',
    };
    unless ( GetOptions( $vars, 'psql-path|pp=s', 'port|p=i', 'username|U=s', 'host|h=s', 'log-path|lp=s', 'gzip-path|gp=s', 'dbname|d=s', 'help|?' ) ) {
        $self->show_help_and_die();
    }
    $self->show_help_and_die() if $vars->{ 'help' };

    # copy key/values from $vars to $self;
    @{ $self }{ keys %{ $vars } } = values %{ $vars };

    return;
}

sub show_help_and_die {
    my $self = shift;
    my ( $format, @args ) = @_;

    if ( $format ) {
        $format =~ s/\s*\z/\n\n/;
        printf STDERR $format, @args;
    }
    print STDERR <<_END_OF_HELP_;
Syntax:
    $PROGRAM_NAME [options]

Options:
    [ database connection options]
      -h,  --host=HOSTNAME      database server host or socket directory
      -p,  --port=PORT          database server port
      -U,  --username=USERNAME  database user name
      -d,  --dbname=DBNAME      database name to connect

    [ paths ]
      -lp, --log-path=PATH      directory where audit logs will be stored
      -pp, --psql-path=PATH     path to psql program
      -gp, --gzip-path=PATH     path to gzip program

    [ other ]
      -?,  --help               show this help page

Defaults:
    --dbname postgres
    --log-path .
    --psql-path psql
    --gzip-path gzip

Description:
    This program connects to PostgreSQL database (via psql), and logs (to compressed files) content of:
    - pg_stat_database
    - pg_stat_all_tables
    - pg_stat_all_indexes
    - pg_statio_all_tables
    - pg_statio_all_indexes
    First view (pg_stat_database) is fetched from only one database, as it contains data about all of them.
    Following four views, are fetched separately for every database in given PostgreSQL installation.

    Output of this is timestamped, and stored in compressed (gzip) files in given directory.

    To simplify geting small time frames of data, datafiles are automatically rotated every hour. To prevent
    creation of thousands of files in single directory, logs are stored in hierarchical directory structure
    which is based on current year and month.

    Data, after decompression, can be loaded to PostgreSQL, or analyzed using any other tools.

    Each row, based on row from one of logged tables, contains (at the beginning) one extra column, with
    timestamp in format:
    YYYY-MM-DD HH-MM-SS
    for example: 2010-06-15 21:34:56

_END_OF_HELP_
    exit( 1 );
}

