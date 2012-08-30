package Data::PcAxis;

# ABSTRACT: A simple interface to the PC-Axis file format

use Moose;
use namespace::autoclean;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;

use 5.010;
use autodie;
use List::AllUtils qw/reduce any firstidx indexes/;
use Carp;
use Text::CSV;

subtype 'AbsFilePath'
  => as 'Path::Class::File';

coerce 'AbsFilePath'
  => from 'Str'
  => via { Path::Class::File->new( $_ )->absolute };

has 'pxfile' => (
    is => 'ro',
    isa => 'AbsFilePath',
    required => 1,
    coerce => 1,
);

has 'metadata' => (
    is => 'ro',
    traits => ['Hash'],
    isa => 'HashRef',
    required => 1,
    builder => '_build_metadata',
    lazy => 1,
    handles => {
	keywords => 'keys',
    },
);

has '_variables' => (
    is => 'ro',
    traits => ['Array'],
    isa => 'ArrayRef',
    required => 1,
    builder => '_build_variables',
    lazy => 1,
    handles => {
	variables => 'elements',
	var_by_idx => 'get',
    },
);

has '_data' => (
    is => 'ro',
    isa => 'ArrayRef',
    required => 1,
    builder => '_build_data',
    lazy => 1,
);

# Allow constructor to accept unnamed argument
around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;

    if ( @_ == 1 && ! ref $_[0] ) {
	return $class->$orig(pxfile => $_[0]);
    }
    else {
	return $class->$orig(@_);
    }
};

sub BUILD {
    my $self = shift;

    # Insert empty array if HEADING is missing from metadata
    if (not exists $self->metadata->{HEADING}) {
	$self->metadata->{HEADING} = {TABLE => []};
    }
}

sub keyword {
    my $self = shift;
    my $keyword = shift;

    if ( defined $self->metadata->{$keyword}->{TABLE} ) {
	return $self->metadata->{$keyword}->{TABLE};
    }
    else {
	return $self->metadata->{$keyword};
    }
}

sub var_by_rx {
    my $self = shift;
    my $find = shift;

    return my $idx = firstidx { $_ =~ $find } $self->variables;
}

sub vals_by_idx {
    my $self = shift;
    my $idx = shift;

    my $var = $self->var_by_idx($idx);
    return $self->keyword('VALUES')->{$var};
}

sub vals_by_name {
    my $self = shift;
    my $var = shift;

    return $self->keyword('VALUES')->{$var};
}

sub codes_by_idx {
    my $self = shift;
    my $idx = shift;

    my $var = $self->var_by_idx($idx);;
    return $self->keyword('CODES')->{$var};
}

sub codes_by_name {
    my $self = shift;
    my $var = shift;

    return $self->keyword('CODES')->{$var};
}

sub _build_variables {
    my $self = shift;

    my @stub = ref $self->keyword('STUB') ? @{$self->keyword('STUB')} : $self->keyword('STUB');
    my @heading = ref $self->keyword('HEADING') ? @{$self->keyword('HEADING')} : $self->keyword('HEADING');

    return [ @stub, @heading ];
}

sub val_counts {
    my $self = shift;

    my @val_counts;

    for my $var ($self->variables) {
	push @val_counts, scalar @{$self->vals_by_name($var)};
    }
    return \@val_counts;
}

sub val_by_code {
    my $self = shift;
    my $var = shift;
    my $code = shift;

    my $vals = $self->vals_by_name($var);
    my $codes = $self->codes_by_name($var);
    my $codeidx = firstidx { $_ eq $code } @$codes;

    return $codeidx == -1 ? $code : $vals->[$codeidx];
}

sub code_by_val {
    my $self = shift;
    my $var = shift;
    my $val = shift;

    my $codes = $self->codes_by_name($var);
    my $vals = $self->vals_by_name($var);
    my $validx = firstidx { $_ eq $val; } @$vals;

    return $validx == -1 ? $val : $codes->[$validx];
}

sub datapoint {
    my $self = shift;
    my $selection = shift;

    my $counts = $self->val_counts;

    my $index;
    for my $n (0..($#$selection - 1)) {
 	$index += $selection->[$n] * (reduce { $a * $b } @$counts[$n+1 .. $#$counts]);
    }
    $index += @$selection[-1];
    return $self->_data->[$index];
}

sub datacol {
    # TODO: Only allow one wildcard.

    my $self = shift;
    my $selection = shift;

    my $counts = $self->val_counts;

    my $datacol;
    if ( any { $_ eq '*' } @$selection ) {
	my $grp_idx = firstidx { $_ eq '*' } @$selection;

	for my $i ( 0 .. (@$counts[$grp_idx] -1 )) {
	    say "i: $i";
	    $selection->[$grp_idx] = $i;
	    push @$datacol, $self->datapoint($selection);
	}
    }
    else {
	$datacol = $self->datapoint($selection);
    }
    return $datacol;
}

sub dataset {} # only allow 2 wildcards

sub _build_metadata {
    my $self = shift;

    open my $fh, '<', $self->pxfile;

    # slurp all metadata into one string, removing newlines
    my $meta = '';
    while (my $line = <$fh>) {
	last if $line =~ /^DATA=/;
	my $tmp = $meta;
	$line =~ s/\R//g;

	# double up end-of-line semicolons to solve problem of semicolons appearing within fields
	$line =~ s/;$/;;/g;
	$meta = $tmp . $line;
    }

    close $fh;

    # join broken lines (e.g. TITLE="...Very Long"\n"Title")
    $meta =~ s/""/ /g;

    # split metadata string into array
    my @meta = split ';;', $meta;

    # initialise Text::CSV objects for parsing options and values
    my $csv_opt = Text::CSV->new({binary=>1}) or die Text::CSV->error_diag();
    my $csv_val = Text::CSV->new({binary=>1}) or die Text::CSV->error_diag();

    # parse metadata array into a hash
    my $metadata;
    for my $i (0..$#meta) {

	# Regex grabs key, option (optional value appearing after key in brackets, used
	# to specify values to which this metadata key refers), and values from each
	# metadata entry
	my ($key, $opt, $val) = $meta[$i] =~ /^(?<key>.+?)(?:\((?<opt>.+?)\))?=(?<val>.+)$/;

	# if entry has no 'option' value then data is specific to table
	$opt //= 'TABLE';

	# parse comma separated list of values to array
	$csv_val->parse($val);
	my @val_fields = $csv_val->fields();

	# parse comma separated list of options to array
	$csv_opt->parse($opt);
	my @opt_fields = $csv_opt->fields();

	# add array of values to appropriate key->option branch of metadata hash
	for my $field (@opt_fields) {
	    $metadata->{$key}->{$field} = scalar @val_fields == 1 ? $val_fields[0] : [ @val_fields ];
	}
    }
    return $metadata;
}

sub _build_data {
    my $self = shift;

    open my $fh, '<', $self->pxfile;

    my @data;
    my $dataflag = 0;
  DATAROW:
    while (my $line = <$fh>) {

	if ($line =~ /^DATA=/) {
	    $dataflag = 1;
	    next DATAROW;
	}
	next DATAROW unless $dataflag == 1;

	chomp $line;
	$line =~ s/;//;
	my @row = split /\s+/, $line;
	push @data, @row;

    }
    return \@data;
}


__PACKAGE__->meta->make_immutable;

1;


__END__

=head1 SYNOPSIS

    use Data::PcAxis;

    # Constructor
    my $px = Data::PcAxis->new('path/to/pcaxis/file');

    # Basic metadata access
    my $metadata  = $px->metadata;
    my @keywords  = $px->keywords;
    my $value     = $px->keyword($keyword);

    # Accessing variables
    my @vars      = $px->variables;
    my $num_vars  = $px->variables;
    my $var_name  = $px->var_by_idx($idx);
    my $index     = $px->var_by_rx($regex);
    my @indices   = TODO

    # Accessing values and codes for variables...
    ## ...by index
    my $val_names = $px->vals_by_idx($var_idx);
    my $val_codes = $px->codes_by_idx($var_idx);

    ## ...by name
    my $val_names = $px->vals_by_name($var_name);
    my $val_codes = $px->codes_by_name($var_name);

    ## count number of possible values for each variable
    my $counts    = $px->val_counts;

    ## Accessing codes for values and vice versa
    my $val_name  = $px->val_by_code($var_name, $val_code);
    my $val_code  = $px->code_by_val($var_name, $val_name);

    # Accessing data
    ## Return a single datum
    my $datum     = $px->datapoint(@indices);

    ## Return a column of data
    my $datacol   = $px->datacol(['*', $idx_1, $idx_2, $idx_n]);

    ## Return a matrix of data
    my $dataset = $px->dataset(['*', '*', $idx_2, $idx_n], 0);

=head1 DESCRIPTION

Data::PcAxis is a module for extracting data (and metadata) from PC-Axis files.

PC-Axis is a file format format used for dissemination of statistical information. The format is used by a number of national statistical organisations to disseminate official statistics.

=head1 TERMINOLOGY

The following terms have the following specific meanings in this document:

=over

=item *

B<Keyword>

This is the top level key of the metadata hash and is equivalent to the PC-Axis I<Keyword> defined in the PC-Axis file format specification (see L</REFERENCES>). Keywords are generally CAPITALISED. Examples of keywords would be TITLE, STUB, HEADING, SOURCE, or DATA.

=item *

B<Variable>

A I<variable> refers to any of the items that appear under the STUB or HEADING keywords in a PC-Axis dataset. Each value in the DATA section of the dataset represents the combination of a specific value for each variable defined in the metadata. Variables are often referred to in code by array index. A variable's index is its position in a zero-based array consisting of the concatenation of the dataset's STUBs followed by its HEADINGs.

=item *

B<Value>

A I<value> is any of the possible values for a I<variable>. Each variable has at least one possible value. Values can be refferred to by I<name> or I<code>.

=item *

B<Name>

A I<name> is the name of a specific I<value>. For example, the names for possible values for the variable DAY might be 'Monday, Tuesday, Wednesday... etc.'

=item *

B<Code>

A I<code> is another way to refer to a possible I<value> for a I<variable>. In general, a value's name is for humans to read and its code is for machines. The codes for the DAY example above might be '01, 02, 03... etc' or 'MON, TUE, WED... etc'.

=item *

B<Datum>

A _datum_ is a single data value held in the data array of the Data::PcAxis object or the DATA keyword of the PC-Axis file. Each datum is the value associated with a particular combination of variable values. The number of _datum_s (data) in a PC-Axis dataset is equal to the product of the number of possible values for each variable &sum

=back

=head1 METHODS

=head2 new

     my $px = Data::PcAxis->new('path/to/pcaxis/file');

Creates a new Data::PcAxis object. Takes the path (relative or absolute) to the PC-Axis file that will be represented by the object.

=head2 metadata

     my $hashref = $px->metadata; //

Returns a hashref containing the PC-Axis file's metadata. Each of the returned hashref's keys is a metadata B<keyword> from the original PC-Axis file, each of its values is a hashref. Where a keyword in the original PC-Axis file has a single string value (meaning that the value applies to the entire dataset --- e.g. the 'TITLE' keyword), then that keyword's hashref contains a single key, 'TABLE', the value of which is the string to which that keyword pointed to in the original PC-Axis file.

=head2 keywords

    my @keywords = $px->keywords;

Returns an array containing all of the metadata B<keywords> associated with the PC-Axis datasets currently represented by the object.

=head2 keyword

   my $value = $px->keyword('TITLE'); // Returns the value of the 'TITLE' keyword

The keyword method returns the value of the passed B<keyword>. If the keyword holds a value which refers to the entire table (such as the 'TITLE' keyword), then that value is returned as a string. If the keyword passed to the method has different B<values> for each B<variable> (for example, the 'VALUES' and 'CODES' keywords will have a different list of values for each variable), then a hashref pointing to the entire set of values is returned by the method.

=head2 variables

    my $num_vars = $px->variables; // scalar context
    my @vars = $px->variables; // list context

In a scalar context the variables method returns the number of B<variables> represented in the dataset.

In a list context the method returns an array containing the variable names. The variables in the returned array are ordered as they are in the PC-Axis file; first the 'STUB' variables, followed by the 'HEADING' variables.

=head2 var_by_idx

    my $var_name = $px->var_by_idx($idx);

Returns the variable name, at the index passed, in an array composed of [ STUB variables, HEADING variables ], that is the array returned by C<Data::PcAxis-E<gt>variables>.

=head2 var_by_rx

    my $index = $px->var_by_rx($pattern);

Returns the index in an array composed of [ STUB variables, HEADING variables ], that is the array returned by C<Data::PcAxis-E<gt>variables>, of the first variable the name of which matches the passed pattern.

=head2 vals_by_idx

    my $val_names = $px->vals_by_idx($var_idx);

Takes a B<variable> index and returns a reference to an array containing the B<names> of all possible B<values> for the variable represented by that index. The order of the values in the array matches the order in the original file. The order will also match that of arrayrefs returned by C<Data::PcAxis-E<gt>codes_by_idx>, C<Data::PcAxis-E<gt>vals_by_name>, and C<Data::PcAxis-E<gt>codes_by_name>.

=head2 codes_by_idx

    my $val_codes = $px->codes_by_idx($var_idx);

Takes a B<variable> index and returns a reference to an array containing the B<codes> for all of the possible B<values> of the variable represented by that index. The order of the codes in the array matches the order in the original file. The order will also match that of arrayrefs returned by C<Data::PcAxis-E<gt>vals_by_idx>, C<Data::PcAxis-E<gt>vals_by_name>, and C<Data::PcAxis-E<gt>codes_by_name>.

=head2 vals_by_name

    my $val_names = $px->vals_by_name($var_name);

Takes a B<variable> name and returns a reference to an array containing the B<names> of all possible B<values> for that variable. The order of the values in the array matches the order in the original file. The order will also match that of arrayrefs returned by C<Data::PcAxis-E<gt>vals_by_idx>, C<Data::PcAxis-E<gt>codes_by_idx>, and C<Data::PcAxis-E<gt>codes_by_name>.

=head2 codes_by_name

    my $val_codes = $px->codes_by_name($var_name);

Takes a B<variable> index and returns a reference to an array containing the B<codes> for all of the possible B<values> of that variable. The order of the codes in the array matches the order in the original file. The order will also match that of arrayrefs returned by C<Data::PcAxis-E<gt>vals_by_idx>, C<Data::PcAxis-E<gt>codes_by_idx>, and C<Data::PcAxis-E<gt>vals_by_name>.

=head2 val_counts

    my $counts = $px->val_counts;

Returns a reference to an array of B<value> counts. Each element in the array is the number of possible values in the current PC-Axis dataset for the variable with the same index (in C<Data::PcAxis-E<gt>variables>) as the element.

=head2 val_by_code

    my $val_name = $px->val_by_code($var_name, $val_code);

=head2 code_by_val

    my $val_code = $px->code_by_val($var_name, $val_name);

=head2 datapoint

    my $datum = $px->datapoint(@indices);

=head2 datacol

    my $datacol = $px->datacol(['*', $idx_1, $idx_2, $idx_n]);


=head2 dataset

    my $dataset = $px->dataset(['*', '*', $idx_2, $idx_n], 0);

=head1 REFERENCES

=over

=item *
PC-Axis web site (L<http://www.scb.se/pc-axis>)

=item *
PC-Axis file format specification (L<http://www.scb.se/Pages/List____314011.aspx>)

=back

=cut

