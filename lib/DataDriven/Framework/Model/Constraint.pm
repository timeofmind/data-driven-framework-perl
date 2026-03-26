package DataDriven::Framework::Model::Constraint;

use strict;
use warnings;
use Moo;
use Carp qw(croak);

# kind: unique | index
has kind    => (is => 'ro', required => 1);
has name    => (is => 'ro', default  => sub { undef });   # optional explicit name
has columns => (is => 'ro', required => 1);               # arrayref of column names
has owner   => (is => 'rw', default  => sub { undef });   # owning class name

my %VALID_KINDS = map { $_ => 1 } qw(unique index);

sub BUILD {
    my ($self) = @_;
    croak "Constraint: unknown kind '" . $self->kind . "'"
        unless $VALID_KINDS{$self->kind};
    croak "Constraint: columns must be a non-empty arrayref"
        unless ref($self->columns) eq 'ARRAY' && @{$self->columns};
}

sub is_unique { $_[0]->kind eq 'unique' }
sub is_index  { $_[0]->kind eq 'index'  }

# Generate a constraint name from table name + columns if no explicit name given
sub effective_name {
    my ($self, $table) = @_;
    return $self->name if defined $self->name;
    my $prefix = $self->is_unique ? 'uq' : 'idx';
    return join('_', $prefix, $table, @{$self->columns});
}

sub column_list {
    my ($self) = @_;
    return join(', ', map { "`$_`" } @{$self->columns});
}

1;

__END__

=head1 NAME

DataDriven::Framework::Model::Constraint - A database constraint (unique or index)

=head1 ATTRIBUTES

=over 4

=item C<kind> (required) - unique | index

=item C<name> (optional) - Explicit constraint name; auto-generated if omitted

=item C<columns> (required) - Arrayref of column names in the constraint

=back

=head1 METHODS

=over 4

=item C<effective_name($table)>

Returns the constraint name, generating one from table+columns if needed.

=item C<column_list()>

Returns a backtick-quoted, comma-separated column list.

=back

=cut
