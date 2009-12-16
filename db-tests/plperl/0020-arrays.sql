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
    SELECT plan(8);

    SELECT lives_ok( 'CREATE LANGUAGE plperl', 'Language creation should work fine?!' );

    SELECT lives_ok( E'CREATE function test1(int4[]) RETURNS INT4 as $$my $i = shift; die "x1 [$i]\\n" unless $i =~ s/^\{(-?\\d+(?:,-?\\d+)*)\}$/$1/; my @a = split /,/, $i; my $q = 0; $q+=$_ for @a; return $q$$ language plperl');

    SELECT is( test1(ARRAY[5,10,15]), 30 );
    SELECT is( test1(ARRAY[-517, 20, 84, -600, 1030]), 17 );

    SELECT lives_ok(
        $FUNC$
        CREATE function test2(TEXT[]) RETURNS TEXT as $$
            my $string = shift || '';
            die "x2 [$string]\n" unless $string =~ s/\A\{(.*)\}\z/$1/;
            my @elements = ();
            my $current = '';
            my $in_quotes = undef;
            my @chars = split //, $string;
            for (my $i = 0 ; $i < scalar @chars; $i++) {
                my $char = $chars[$i];
                if ($char eq ',') {
                    if ($in_quotes) {
                        $current .= $char;
                    } else {
                        push @elements, $current;
                        $current = '';
                    }
                } elsif ( $char eq '"') {
                    $in_quotes = !$in_quotes;
                } elsif ( ($char eq '\\') && ( $in_quotes ) ) {
                    $i++;
                    $current .= $chars[$i];
                } else {
                    $current .= $char;
                }
            }
            push @elements, $current;
            return "[" . join("],[", sort @elements) . "]";
        $$ language plperl
        $FUNC$
    );

    SELECT is( test2( ARRAY[ 'a', 'z', 'b', 'p', 'c' ] ), '[a],[b],[c],[p],[z]' );
    SELECT is( test2( ARRAY[ E'x\\r', 'a'] ), E'[a],[x\\r]' );
    SELECT is( test2( ARRAY[ 'a''qq', 'b'] ), '[a''qq],[b]' );

    SELECT * FROM finish();
ROLLBACK;
