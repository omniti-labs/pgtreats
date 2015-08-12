#!/opt/OMNIperl/bin/perl

# UTF8 boilerplace, per http://stackoverflow.com/questions/6162484/why-does-modern-perl-avoid-utf-8-by-default/
use v5.10;
use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :std :utf8 );
use lib '/opt/OMNIperl/lib/vendor_perl/5.16';
use autodie;

# UTF8 boilerplace, per http://stackoverflow.com/questions/6162484/why-does-modern-perl-avoid-utf-8-by-default/

use Carp;
use English qw( -no_match_vars );

use HTML::Tree;

my $tree = HTML::TreeBuilder->new_from_file( \*STDIN );
$tree->elementify();

$_->delete() for $tree->look_down( _tag => qr{\A(?:script|style)\z} );

$_->delete() for $tree->look_down( _tag => "div", class => qr{\bnavbar-inner\b}, );
$_->delete() for $tree->look_down( _tag => "ul",  class => qr{\bnav-tabs\b}, );

$_->delete() for $tree->look_down(
    _tag => "div", id => qr{\A(?:
top
| tab-events
| tab-vacuums
| tab-tempfiles
| tab-sessions
| tab-connections
| sql-traffic
| select-traffic
| write-traffic
| duration-traffic
| general-activity
| prepared-queries-ratio
| littleToc
)\z}x
);

$_->delete() for $tree->look_down(
    _tag => "li", id => qr{\A(?:
connections-slide
| sessions-slide
| checkpoints-slide
| tempfiles-slide
| vacuums-slide
| locks-slide
| queries-slide
| events-slide
)\z}x
);

$_->parent()->delete() for $tree->look_down( _tag => 'small', class => qr{\bpull-right\b} );

my ( $top_queries ) = $tree->look_down( _tag => 'li', id => 'topqueries-slide' );

$_->delete() for $top_queries->look_down( _tag => 'div', class => qr{\bcollapse\b} );

$_->delete() for $top_queries->look_down( _tag => qr{\A(?:a|button)\z}, class => qr{\bbtn\b} );

for my $td ( $top_queries->look_down( _tag => 'td', id => qr{.*-rank-\d+\z} ) ) {
    my $id = $td->attr( 'id' );
    $id =~ s/.*-//;
    next if $id <= 10;
    $td->parent()->delete();
}

for my $tag ( $tree->look_down( onclick => qr{\S} ) ) {
    $tag->attr( 'onclick', undef );
}

for my $sql ( $tree->look_down( _tag => 'div', class => qr{\bsql\b} ) ) {
    $_->replace_with_content() for $sql->look_down( _tag => 'span' );
}

print $tree->as_XML();

exit;
