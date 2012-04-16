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

my $values = {
          'Year' => [
                      '2008',
                      '2009'
                    ],
          'Industry Sector NACE Rev 2' => [
                                            'Textiles (13)',
                                            'Wearing apparel (14)',
                                            'Wood and wood products, except furniture (16)',
                                            'Paper and paper products (17)',
                                            'Printing and reproduction of recorded media (18)',
                                            'Rubber and plastic products (22)',
                                            'Other non-metallic mineral products (23)',
                                            'Basic metals (24)',
                                            'Fabricated metal products, except machinery and equipment (25)',
                                            'Computer, electronic and optical products (26)',
                                            'Electrical equipment (27)',
                                            'Machinery and equipment n.e.c. (28)',
                                            'Motor vehicles, trailers and semi-trailers (29)',
                                            'Repair and installation of machinery and equipment (33)',
                                            'Food; chemical and pharmaceutical products (10,20,21)',
                                            'Food, chemical, pharmaceutical products, computer and optical products (10,20,21,26)',
                                            'Manufacturing industries (10 to 33)',
                                            'Beverages; tobacco; coke and refined petroleum products; furniture (11,12,19,31)',
                                            'Leather, electrical, motor vehicles, trailers, transport, other manufacturing (15,27,29,30,32)',
                                            'Leather; other transport equipment and other manufacturing (15,30,32)'
                                          ],
          'Region' => [
                        'Border, Midland and Western',
                        'Southern and Eastern',
                        'State'
                      ],
          'Statistic' => [
                           'Manufacturing Local Units (Number)',
                           'Persons Engaged in Manufacturing Local Units (Number)',
                           'Gross Output in Manufacturing Local Units (Euro Thousand)',
                           'Gross Output Exported (Euro Thousand)',
                           'Distribution of Output Exported - UK (Euro Thousand)',
                           'Distribution of Output Exported - EU Excl UK (Euro Thousand)',
                           'Distribution of Output Exported - USA (Euro Thousand)',
                           'Distribution of Output Exported - Rest of World (Euro Thousand)'
                         ]
        };

is_deeply( $px->keyword('VALUES'), $values, 'Keyword with HoH returned');

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

