package Data::PcAxis;

# ABSTRACT: A simple interface to the Pc-Axis file format

use Moose;
use namespace::autoclean;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;

use 5.010;
use autodie;
use List::AllUtils qw/reduce any firstidx/;
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
	my $file = $self->pxfile;
	$self->_metadata->{HEADING} = {TABLE => []};
    }
}

sub keyword {
    my $self = shift;
    my $keyword = shift;

    if ( defined $self->_metadata->{$keyword}->{TABLE} ) {
	return $self->_metadata->{$keyword}->{TABLE};
    }
    else {
	return $self->_metadata->{$keyword};
    }
}

sub var_by_rx {
    my ($self, $find) = @_;

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

sub dataset {
    my $self = shift;
    my $selection = shift;

    my $counts = $self->val_counts;

    my $dataset;
    if ( any { $_ eq '*' } @$selection ) {
	my $grp_idx = firstidx { $_ eq '*' } @$selection;

	for my $i ( 0 .. (@$counts[$grp_idx] -1 )) {
	    $selection->[$grp_idx] = $i;
	    push @$dataset, $self->datapoint($selection);
	}
    }
    else {
	$dataset = $self->datapoint($selection);
    }
    return $dataset;
}

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

    # convert double-semicolons to newlines
    $meta =~ s/;;/\n/g;

    # join broken lines (e.g. TITLE="...Very Long"\n"Title")
    $meta =~ s/""/ /g;

    # split metadata string into array
    my @meta = split '\n', $meta;

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

    my $px = Data::PcAxis->new('path/to/pcaxis/file');

    my $metadata  = $px->metadata;
    my @keywords  = $px->keywords;
    my $value     = $px->keyword($keyword);

    my @vars      = $px->variables;
    my $num_vars  = $px->variables;
    my $var_name  = $px->var_by_idx($idx);
    my $index     = $px->var_by_rx($regex);
    my @indices   = TODO

    my $val_names = $px->vals_by_idx($var_idx);
    my $val_codes = $px->codes_by_idx($var_idx);

    my $val_names = $px->vals_by_name($var_name);
    my $val_codes = $px->codes_by_name($var_name);

    my $counts    = $px->val_counts;

    my $val_name  = $px->val_by_code($var_name, $val_code);
    my $val_code  = $px->code_by_val($var_name, $val_name);

    my $datum     = $px->datapoint(@indices);
    my $dataset   = $px->dataset(['*', $idx_1, $idx_2, $idx_n]);

=head1 DESCRIPTION

Data::PcAxis is a module for extracting data (and metadata) from PC-Axis files.

PC-Axis is a file format format used for dissemination of statistical information. The format is used by a number of national statistical organisations to disseminate national statistics.

=head1 METHODS

=head2 new

     my $px = Data::PcAxis->new('path/to/pcaxis/file');

Creates a new Data::PcAxis object. Takes the path (relative or absolute) to the PC-Axis file that will be represented by the object.

=head2 metadata

     $px->metadata; // 

=head1 REFERENCES

=cut

