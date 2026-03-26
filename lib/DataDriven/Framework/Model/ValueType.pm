package DataDriven::Framework::Model::ValueType;

use strict;
use warnings;

# Supported primitive types and their MySQL / JSON Schema / Perl mappings.
# This is a plain package of constants and helper subs, not an OO class.

our @PRIMITIVE_TYPES = qw(
    string
    integer
    float
    boolean
    date
    datetime
    text
    enum
);

my %MYSQL_TYPE_MAP = (
    string   => 'VARCHAR(255)',
    integer  => 'INT',
    float    => 'DOUBLE',
    boolean  => 'TINYINT(1)',
    date     => 'DATE',
    datetime => 'DATETIME',
    text     => 'TEXT',
    enum     => 'ENUM',   # expanded by SQL generator using enum values
);

my %JSON_SCHEMA_TYPE_MAP = (
    string   => { type => 'string' },
    integer  => { type => 'integer' },
    float    => { type => 'number' },
    boolean  => { type => 'boolean' },
    date     => { type => 'string', format => 'date' },
    datetime => { type => 'string', format => 'date-time' },
    text     => { type => 'string' },
    enum     => { type => 'string' },   # enum values added by generator
);

my %PERL_TYPE_MAP = (
    string   => 'Str',
    integer  => 'Int',
    float    => 'Num',
    boolean  => 'Bool',
    date     => 'Str',
    datetime => 'Str',
    text     => 'Str',
    enum     => 'Str',
);

my %HTML_INPUT_MAP = (
    string   => 'text',
    integer  => 'number',
    float    => 'number',
    boolean  => 'checkbox',
    date     => 'date',
    datetime => 'datetime-local',
    text     => 'textarea',
    enum     => 'select',
);

sub is_valid {
    my ($class, $type) = @_;
    return grep { $_ eq $type } @PRIMITIVE_TYPES;
}

sub mysql_type {
    my ($class, $type) = @_;
    return $MYSQL_TYPE_MAP{$type} // 'VARCHAR(255)';
}

sub json_schema_type {
    my ($class, $type) = @_;
    return $JSON_SCHEMA_TYPE_MAP{$type} // { type => 'string' };
}

sub perl_type {
    my ($class, $type) = @_;
    return $PERL_TYPE_MAP{$type} // 'Str';
}

sub html_input_type {
    my ($class, $type) = @_;
    return $HTML_INPUT_MAP{$type} // 'text';
}

# Map a MySQL column type back to our type system (for reverse generator)
sub from_mysql_type {
    my ($class, $mysql_type) = @_;
    $mysql_type = uc($mysql_type);
    $mysql_type =~ s/\(.*\)//;  # strip size/precision
    $mysql_type =~ s/\s+UNSIGNED//;
    return 'integer'  if $mysql_type =~ /^(INT|INTEGER|BIGINT|SMALLINT|TINYINT|MEDIUMINT)$/;
    return 'boolean'  if $mysql_type eq 'TINYINT';   # ambiguous; caller must check size
    return 'float'    if $mysql_type =~ /^(FLOAT|DOUBLE|DECIMAL|NUMERIC|REAL)$/;
    return 'boolean'  if $mysql_type eq 'BOOLEAN';
    return 'date'     if $mysql_type eq 'DATE';
    return 'datetime' if $mysql_type =~ /^(DATETIME|TIMESTAMP)$/;
    return 'text'     if $mysql_type =~ /^(TEXT|MEDIUMTEXT|LONGTEXT|TINYTEXT|BLOB|MEDIUMBLOB|LONGBLOB)$/;
    return 'enum'     if $mysql_type eq 'ENUM';
    return 'string';  # VARCHAR, CHAR, etc.
}

1;

__END__

=head1 NAME

DataDriven::Framework::Model::ValueType - Type system for schema fields

=head1 DESCRIPTION

A utility package providing type mappings between the framework's type system
and MySQL, JSON Schema, Perl, and HTML input types.

=head1 PRIMITIVE TYPES

C<string>, C<integer>, C<float>, C<boolean>, C<date>, C<datetime>, C<text>, C<enum>

=head1 CLASS METHODS

=over 4

=item C<is_valid($type)>

Returns true if C<$type> is a known primitive type.

=item C<mysql_type($type)>

Returns the MySQL DDL type string for the given primitive type.

=item C<json_schema_type($type)>

Returns a hashref suitable for embedding in a JSON Schema definition.

=item C<perl_type($type)>

Returns the Type::Tiny type name for the given primitive type.

=item C<html_input_type($type)>

Returns the HTML input type string.

=item C<from_mysql_type($mysql_type)>

Maps a MySQL column type back to a framework primitive type.

=back

=cut
