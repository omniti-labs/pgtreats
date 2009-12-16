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
    SELECT plan(3);

    SELECT lives_ok( 'CREATE LANGUAGE plperl', 'Language creation should work fine?!' );

    CREATE type t1_srf as ( x TEXT, i INT4 );
    SELECT lives_ok( E'CREATE function test1() RETURNS setof t1_srf as $$ return [ { "x" => "r1", "i" => 100 }, {"x" => "r2", "i" => 200} ]; $$ language plperl');

    SELECT results_eq(
        'SELECT * FROM test1()',
        $$VALUES ( 'r1', 100 ), ('r2', 200)$$
    );

    SELECT * FROM finish();
ROLLBACK;
