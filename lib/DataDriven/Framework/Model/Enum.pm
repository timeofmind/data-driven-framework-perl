package DataDriven::Framework::Model::Enum;

use strict;
use warnings;
use Moo;
use Carp qw(croak);

has name        => (is => 'ro', required => 1);
has values      => (is => 'ro', required => 1);   # arrayref of strings
has default     => (is => 'ro', default  => sub { undef });
has description => (is => 'ro', default  => sub { '' });

sub BUILD {
    my ($self) = @_;
    croak "Enum '" . $self->name . "': values must be a non-empty arrayref"
        unless ref($self->values) eq 'ARRAY' && @{$self->values};

    if (defined $self->default) {
        my %valid = map { $_ => 1 } @{$self->values};
        croak "Enum '" . $self->name . "': default '" . $self->default
            . "' is not in values list"
            unless $valid{$self->default};
    }
}

sub has_value {
    my ($self, $value) = @_;
    return grep { $_ eq $value } @{$self->values};
}

sub mysql_enum_list {
    my ($self) = @_;
    return join(', ', map { "'$_'" } @{$self->values});
}

1;

__END__

=head1 NAME

DataDriven::Framework::Model::Enum - Represents a named enumeration

=head1 SYNOPSIS

    my $enum = DataDriven::Framework::Model::Enum->new(
        name    => 'Status',
        values  => [qw(active inactive deleted)],
        default => 'active',
    );

=head1 ATTRIBUTES

=over 4

=item C<name> (required) - The enum name

=item C<values> (required) - Arrayref of string values

=item C<default> (optional) - Default value; must be in C<values>

=item C<description> (optional) - Documentation string

=back

=head1 METHODS

=over 4

=item C<has_value($value)>

Returns true if C<$value> is a member of this enum.

=item C<mysql_enum_list()>

Returns a comma-separated, quoted list suitable for MySQL ENUM(...).

=back

=cut
