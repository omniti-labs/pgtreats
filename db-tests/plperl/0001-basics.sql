\set ECHO
\set QUIET 1

\pset format unaligned
\pset tuples_only true
\pset pager

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true
\set QUIET 1

BEGIN;
    SELECT plan(18);

    SELECT lives_ok( 'CREATE LANGUAGE plperl', 'Language creation should work fine?!' );

    SELECT throws_ok( 'CREATE function x() RETURNS TEXT as $$xx++$$ language plperl');

    SELECT throws_ok( 'CREATE function x() RETURNS TEXT as $$use Data::Dumper;$$ language plperl');

    SELECT lives_ok( 'CREATE function x_text() RETURNS TEXT as $$return "Test String"$$ language plperl', 'Returning TEXT');
    SELECT ok( x_text() = 'Test String'::TEXT, 'Simple call to function returning TEXT');

    SELECT lives_ok( 'CREATE function x_int4() RETURNS INT4 as $$return 567123$$ language plperl', 'Returning INT4');
    SELECT ok( x_int4() = 567123::INT4, 'Simple call to function returning INT4');

    SELECT lives_ok( 'CREATE function x_numeric() RETURNS NUMERIC as $$return 123.456$$ language plperl', 'Returning NUMERIC');
    SELECT ok( x_numeric() = 123.456::NUMERIC, 'Simple call to function returning NUMERIC');

    SELECT lives_ok( 'CREATE function x_timestamptz() RETURNS TIMESTAMPTZ as $$return q{2008-02-28 17:56:23 EDT}$$ language plperl', 'Returning TIMESTAMPTZ');
    SELECT ok( x_timestamptz() = '2008-02-29 07:56:23 AEST'::TIMESTAMPTZ, 'Simple call to function returning TIMESTAMPTZ');

    SELECT lives_ok( 'CREATE function y_text(TEXT) RETURNS TEXT as $$return scalar reverse shift$$ language plperl', 'Taking and returning TEXT');
    SELECT ok( y_text('OmniTI') = 'ITinmO', 'Simple call to function processing TEXT');

    SELECT lives_ok( 'CREATE function y_int4(INT4) RETURNS INT4 as $$return $_[0] / 2$$ language plperl', 'Taking and returning INT4');
    SELECT throws_ok( 'SELECT y_int4(3) = 1' );
    SELECT ok( y_int4(4) = 2, 'Simple call to function processing INT4');

    SELECT lives_ok( 'CREATE function y_numeric(NUMERIC) RETURNS NUMERIC as $$return $_[0] / 2$$ language plperl', 'Taking and returning NUMERIC');
    SELECT ok( y_numeric(5) = 2.5, 'Simple call to function processing NUMERIC');

    SELECT * FROM finish();
ROLLBACK;
