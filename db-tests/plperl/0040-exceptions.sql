\set ECHO
\set QUIET 1

\pset format unaligned
\pset tuples_only true
\pset pager

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true
\set QUIET 1

SET client_encoding = utf8;

BEGIN;
    SELECT plan(4);

    SELECT lives_ok( 'CREATE LANGUAGE plperl', 'Language creation should work fine?!' );

    SELECT lives_ok( E'CREATE function test1(INT4) RETURNS INT4 as $$ die "TEST\n" if $_[0] == 0; return 1; $$ language plperl');

    SELECT lives_ok( 'SELECT test1(1)' );
    SELECT throws_ok( 'SELECT test1(0)', 'XX000', 'error from Perl function "test1": TEST', 'Basic die() handling' );

    SELECT * FROM finish();
ROLLBACK;
