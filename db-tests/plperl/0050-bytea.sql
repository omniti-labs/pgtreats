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
    SELECT plan(5);

    SELECT lives_ok( 'CREATE LANGUAGE plperl', 'Language creation should work fine?!' );

    SELECT lives_ok(
        $FUNC$
            CREATE function test_output() RETURNS BYTEA as $$
                my $reply = "\000"x6;
                for (1..255) {
                    $reply .= chr($_);
                }
                $reply .= "\000" x 6;
                $reply =~ s/./sprintf "\\%03o", ord $&/ges;
                return $reply;
            $$ language plperl
        $FUNC$
    );

    SELECT ok( test_output() = decode(
        '0000000000000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F202122232425262' ||
        '728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F404142434445464748494A4B4C4D4E4F50515253' ||
        '5455565758595A5B5C5D5E5F606162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F8' ||
        '08182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0A1A2A3A4A5A6A7A8A9AAABAC' ||
        'ADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D' ||
        '9DADBDCDDDEDFE0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF000000000000',
        'hex'));

    SELECT lives_ok(
        $FUNC$
            CREATE function test_input(bytea) RETURNS int4 as $$
                my $reply = 0;
                my $input = shift;
                if ( $input =~ s/^\\x// ) {
                    $input =~ s/([0-9a-f]{2})/chr hex $1/eig;
                } else {
                    $input =~ s/\\([0-7]{3})/chr oct $1/eig;
                }
                for my $char ( split //, $input ) {
                    $reply += ord( $char );
                }
                return $reply;
            $$ language plperl
        $FUNC$
    );
    SELECT is( test_input( decode('00010220', 'hex')), 35);

    SELECT * FROM finish();
ROLLBACK;
