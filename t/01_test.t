#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use autodie;
use Test::More;
use JSON;
use POSIX 'floor';

BEGIN { use_ok 'Data::PcAxis'; }

my $testData;
{
    my $filepath = 't/testData.json';
    open my $testJSON_fh, '<', $filepath;
    local $/;
    $testData = decode_json(<$testJSON_fh>);
    close $testJSON_fh;
}

sub run_tests {
    my ($pxfile, $i) = @_;

    # Construction
    my $px = new_ok('Data::PcAxis' => [$pxfile]);

    # Keyword access (title)
    my $title = $testData->[$i]->{title};
    is($px->keyword('TITLE'), $title, 'Title: ' . $title);

    # Basic metadata access
    my $numkeys = $testData->[$i]->{numKeywords};
    is(ref($px->metadata), 'HASH', 'Hashref returned on metadata request');
    is(scalar keys $px->metadata, $numkeys, "Number of metadata keys: $numkeys");
    is(scalar $px->keywords, $numkeys, "Keywords array length: $numkeys");

    # Variable access (All)
    my $numvars = $testData->[$i]->{numVars};
    is(scalar $px->variables, $numvars, "Number of variables: $numvars");
    is($px->variables, @{$testData->[$i]->{varNames}}, 'Variable names array');

    # Value counts
    my $valcounts = $testData->[$i]->{numVals};
    is_deeply($px->val_counts, $valcounts, 'Array of value counts for each variable correctly returned');

    # Accessing Values and Codes for particular variables
    for my $idx (0 .. $numvars-1) {

	# Variable access by index
	my $varname = $testData->[$i]->{varNames}[$idx];
	is($px->var_by_idx($idx), $varname, "Variable by index: $idx---$varname");

	# Variable access by regex
	my @chars = (substr($varname, 0, 1), substr($varname, -1, 1));
	my $re = qr/^$chars[0].*$chars[1]$/;
	like($px->var_by_idx($px->var_by_rx($re)), $re, "Variable by regex: $re---$varname");

	# Accessing value and code arrays by variable name and index
	## Check for correct number of elements
	my $numvals = $testData->[$i]->{numVals}[$idx];
	is(scalar @{$px->vals_by_idx($idx)}, $numvals, "Number of values for variable at index $idx: $numvals");
	is(scalar @{$px->vals_by_name($varname)}, $numvals, "Number of values for variable $varname: $numvals");
	is(scalar @{$px->codes_by_idx($idx)}, $numvals, "Number of codes for variable at index $idx: $numvals");
	is(scalar @{$px->codes_by_name($varname)}, $numvals, "Number of codes for variable $varname: $numvals");

	## Check array contents (Values by index)
	my @vals = @{$testData->[$i]->{firstMidLastVals}->[$idx]};
	is($px->vals_by_idx($idx)->[0], $vals[0], "First value for variable at index $idx: $vals[0]");
	is($px->vals_by_idx($idx)->[floor($numvals/2)], $vals[1], "Middle value for variable at index $idx: $vals[1]");
	is($px->vals_by_idx($idx)->[-1], $vals[2], "Last value for variable at index $idx: $vals[2]");

	## Check array contents (Values by name)
	is($px->vals_by_name($varname)->[0], $vals[0], "First value for variable $varname: $vals[0]");
	is($px->vals_by_name($varname)->[floor($numvals/2)], $vals[1], "Middle value for variable $varname: $vals[1]");
	is($px->vals_by_name($varname)->[-1], $vals[2], "Last value for variable $varname: $vals[2]");

	## Check array contents (Codes by index)
	my @codes = @{$testData->[$i]->{firstMidLastCodes}->[$idx]};
	is($px->codes_by_idx($idx)->[0], $codes[0], "First code for variable at index $idx: $codes[0]");
	is($px->codes_by_idx($idx)->[floor($numvals/2)], $codes[1], "Middle code for variable at index $idx: $codes[1]");
	is($px->codes_by_idx($idx)->[-1], $codes[2], "Last code for variable at index $idx: $codes[2]");

	## Check array contents (Codes by name)
	is($px->codes_by_name($varname)->[0], $codes[0], "First code for variable $varname: $codes[0]");
	is($px->codes_by_name($varname)->[floor($numvals/2)], $codes[1], "Middle code for variable $varname: $codes[1]");
	is($px->codes_by_name($varname)->[-1], $codes[2], "Last code for variable $varname: $codes[2]");

	# Accessing value-by-code and code-by-value
	for (0..2) {
	    is($px->val_by_code($varname, $codes[$_]), $vals[$_], "Value $vals[$_] returned for code $codes[$_]");
	    is($px->code_by_val($varname, $vals[$_]), $codes[$_], "Code $codes[$_] returned for value $vals[$_]");
	}
    }

    # Accessing data
    ## Count number of data points
    my $num_data = $testData->[$i]->{numData};
    is(scalar @{$px->data}, $num_data, "Number of data points: $num_data");

    my $last_idx = $num_data - 1;
    my $mid_idx = floor($num_data / 2);
    my @datum_arr = 0 x $numvars;
    my $first_datum = $testData->[$i]->{firstDatum};
    is($px->datum(\@datum_arr), $first_datum, "First datum is $first_datum");


}

for my $i (0..$#$testData) {
    my $pxfile = 't/testData/' . $testData->[$i]->{filename};
    run_tests($pxfile, $i);
}

#use Data::Dumper; say Dumper $testData;
#say scalar keys $testData;
#my $px = new_ok('Data::PcAxis' => ['t/testdata/AIA36.px']);

# my @keywords = qw(DATABASE LANGUAGE CONTVARIABLE MATRIX CODES CONTENTS INFOFILE UNITS VALUES SHOWDECIMALS HEADING SUBJECT-CODE LAST-UPDATED DECIMALS STUB CHARSET BASEPERIOD AXIS-VERSION CREATION-DATE TIMEVAL SUBJECT-AREA TITLE REFPERIOD DOMAIN SOURCE);
# is_deeply( [$px->keywords], \@keywords, 'Keywords' );

# my $title = 'Manufacturing Local Units which Export by Region, Industry Sector NACE Rev 2, Year and Statistic';
# is( $px->keyword('TITLE'), $title, 'String value for keyword' );

# my $values = {
#           'Year' => [
#                       '2008',
#                       '2009'
#                     ],
#           'Industry Sector NACE Rev 2' => [
#                                             'Textiles (13)',
#                                             'Wearing apparel (14)',
#                                             'Wood and wood products, except furniture (16)',
#                                             'Paper and paper products (17)',
#                                             'Printing and reproduction of recorded media (18)',
#                                             'Rubber and plastic products (22)',
#                                             'Other non-metallic mineral products (23)',
#                                             'Basic metals (24)',
#                                             'Fabricated metal products, except machinery and equipment (25)',
#                                             'Computer, electronic and optical products (26)',

#                                             'Electrical equipment (27)',
#                                             'Machinery and equipment n.e.c. (28)',
#                                             'Motor vehicles, trailers and semi-trailers (29)',
#                                             'Repair and installation of machinery and equipment (33)',
#                                             'Food; chemical and pharmaceutical products (10,20,21)',
#                                             'Food, chemical, pharmaceutical products, computer and optical products (10,20,21,26)',
#                                             'Manufacturing industries (10 to 33)',
#                                             'Beverages; tobacco; coke and refined petroleum products; furniture (11,12,19,31)',
#                                             'Leather, electrical, motor vehicles, trailers, transport, other manufacturing (15,27,29,30,32)',
#                                             'Leather; other transport equipment and other manufacturing (15,30,32)'
#                                           ],
#           'Region' => [
#                         'Border, Midland and Western',
#                         'Southern and Eastern',
#                         'State'
#                       ],
#           'Statistic' => [
#                            'Manufacturing Local Units (Number)',
#                            'Persons Engaged in Manufacturing Local Units (Number)',
#                            'Gross Output in Manufacturing Local Units (Euro Thousand)',
#                            'Gross Output Exported (Euro Thousand)',
#                            'Distribution of Output Exported - UK (Euro Thousand)',
#                            'Distribution of Output Exported - EU Excl UK (Euro Thousand)',
#                            'Distribution of Output Exported - USA (Euro Thousand)',
#                            'Distribution of Output Exported - Rest of World (Euro Thousand)'
#                          ]
#         };

# my $val_counts = [3, 20, 2, 8];
# is_deeply($px->val_counts, $val_counts, 'val_counts');

# is_deeply($px->keyword('VALUES'), $values, 'Keyword with HoH returned');

# my @variables = ('Region', 'Industry Sector NACE Rev 2', 'Year', 'Statistic');
# is_deeply( [$px->variables], \@variables, 'Variable names (list)' );

# is_deeply( [$px->variables], [ @{$px->metadata->{'STUB'}->{'TABLE'}}, @{$px->metadata->{'HEADING'}->{'TABLE'}} ], 'Variables via metadata attribute');

# is($px->variables, 4, 'Variable count');

# for my $index ( 0..3 ) {
#     is($px->var_by_idx($index), $variables[$index], "Variable name by index: $index");
# }

# is( $px->var_by_idx(5), undef, 'Bad index returns undef' );

# for my $index ( 0..3 ) {
#     is($px->var_by_idx($index), $variables[$index], "Variable name by index: $index");
# }

# my @regexes = (qr/^.egio.$/, qr/\ssector\s/i, qr/^Y.+r$/, qr/stat.stic/i);
# for my $index ( 0..$#regexes ) {
#     is( $px->var_by_rx($regexes[$index]), $index, "Variable name by regex: $index");
# }

# my @strings = ('Regi', 'gio', '^.egio.$');
# for my $string (@strings) {
#     is( $px->var_by_rx($string), 0, "Variable name by rx: -> passed a string: $string");
# }

# my $point = 26;
# is( $px->datapoint([0,0,0,0]), 26, 'single first datapoint');

# my $col = [26, 47, 73];
# is_deeply( $px->datacol(['*',0,0,0]), $col, 'datacol');

done_testing();

