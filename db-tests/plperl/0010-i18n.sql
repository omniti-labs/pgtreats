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
    SELECT plan(19);

    SELECT lives_ok( 'CREATE LANGUAGE plperl', 'Language creation should work fine?!' );

    SELECT lives_ok( 'CREATE function pl_uc(TEXT) RETURNS TEXT as $$return uc shift$$ language plperl', 'Uppercase conversion');
    SELECT lives_ok( 'CREATE function pl_lc(TEXT) RETURNS TEXT as $$return lc shift$$ language plperl', 'Lowercase conversion');
    SELECT lives_ok( 'CREATE function pl_re(TEXT, TEXT) RETURNS TEXT as $$return $_[0] =~ $_[1] ? $& : "NOT MATCHED"$$ language plperl', 'Regexp matching');
    SELECT lives_ok( E'CREATE function pl_euro() RETURNS TEXT as $$return "\\x{20AC}"$$ language plperl', 'Euro character');

    SELECT ok( upper('OmniTI') = 'OMNITI', 'Uppercase sanity check, base string, just a-z letters');
    SELECT ok( pl_uc('OmniTI') = upper('OmniTI'), 'Uppercase, base string, just a-z letters');
    SELECT ok( lower('OmniTI') = 'omniti', 'Lowercase sanity check, base string, just a-z letters');
    SELECT ok( pl_lc('OmniTI') = lower('OmniTI'), 'Lowercase, base string, just a-z letters');

    SELECT ok( 'ZAŻÓŁĆ GĘŚLĄ JAŹŃ' = upper('ZażółĆ gĘŚlą jaŹń'), 'Uppercase polish accented letters' );
    SELECT ok( pl_uc('ZażółĆ gĘŚlą jaŹń') = upper('ZażółĆ gĘŚlą jaŹń'), 'Uppercase polish accented letters' );
    SELECT ok( 'zażółć gęślą jaźń' = lower('ZażółĆ gĘŚlą jaŹń'), 'Lowercase polish accented letters' );
    SELECT ok( pl_lc('ZażółĆ gĘŚlą jaŹń') = lower('ZażółĆ gĘŚlą jaŹń'), 'Lowercase polish accented letters' );

    SELECT ok( pl_re('OmniTI', 'ni') = 'ni' );
    SELECT ok( pl_re('OmniTI', 'n.') = 'ni' );
    SELECT ok( pl_re('Zażółć', 'a..') = 'ażó' );
    SELECT ok( pl_re('Zażółć', 'Ż..') = 'NOT MATCHED' );
    SELECT ok( pl_re('Zażółć', '(?i-xsm:Ż..)') = 'żół' );

    SELECT is( pl_euro(), '€' );

    SELECT * FROM finish();
ROLLBACK;
