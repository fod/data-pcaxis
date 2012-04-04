#!/usr/bin/env perl

use strict;
use warnings;
use Test::Most;

BEGIN { use_ok 'Data::PcAxis'; }
my $px = new_ok('Data::PcAxis' => ['t/testdata/AIA36.px']);

my @keywords = qw(DATABASE LANGUAGE CONTVARIABLE MATRIX CODES CONTENTS INFOFILE UNITS VALUES SHOWDECIMALS HEADING SUBJECT-CODE LAST-UPDATED DECIMALS STUB CHARSET BASEPERIOD AXIS-VERSION CREATION-DATE TIMEVAL SUBJECT-AREA TITLE REFPERIOD DOMAIN SOURCE);
is_deeply( [$px->keywords], \@keywords, 'Keywords' );

my $title = 'Manufacturing Local Units which Export by Region, Industry Sector NACE Rev 2, Year and Statistic';
is( $px->keyword('TITLE'), $title, 'String value for keyword' );

my @variables = ('Region', 'Industry Sector NACE Rev 2', 'Year', 'Statistic');
is_deeply( [$px->variables], \@variables, 'Variable names (list)' );

is($px->variables, 4, 'Variable count');

for my $index ( 0..3 ) {
    is($px->var_by_idx($index), $variables[$index], "Variable name by index: $index");
}

is( $px->var_by_idx(5), undef, 'Bad index returns undef' );

for my $index ( 0..3 ) {
    is($px->var_by_idx($index), $variables[$index], "Variable name by index: $index");
}

my @regexes = (qr/^.egio.$/, qr/\ssector\s/i, qr/^Y.+r$/, qr/stat.stic/i);
for my $index ( 0..$#regexes ) {
    is( $px->var_by_rx($regexes[$index]), $index, "Variable name by regex: $index");
}



done_testing();

