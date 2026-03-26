package DataDriven::Framework::Model::Relationship;

use strict;
use warnings;
use Moo;
use Carp qw(croak);

# kind: belongs_to | has_many | many_to_many
has kind        => (is => 'ro', required => 1);
has name        => (is => 'ro', required => 1);   # auto-derived if not given
has target      => (is => 'ro', required => 1);   # target class name
has via         => (is => 'ro', default  => sub { undef });  # FK field name (belongs_to)
has through     => (is => 'ro', default  => sub { undef });  # join class (many_to_many)
has label       => (is => 'ro', default  => sub { undef });
has description => (is => 'ro', default  => sub { '' });
has required    => (is => 'ro', default  => sub { 0 });

# Owning class name (set by resolver)
has owner       => (is => 'rw', default  => sub { undef });

my %VALID_KINDS = map { $_ => 1 } qw(belongs_to has_many many_to_many);

sub BUILD {
    my ($self) = @_;
    croak "Relationship: unknown kind '" . $self->kind . "'"
        unless $VALID_KINDS{$self->kind};
    croak "Relationship kind=belongs_to requires 'via' (FK field name)"
        if $self->kind eq 'belongs_to' && !defined($self->via);
    croak "Relationship kind=many_to_many requires 'through' (join class name)"
        if $self->kind eq 'many_to_many' && !defined($self->through);
}

sub is_belongs_to  { $_[0]->kind eq 'belongs_to'  }
sub is_has_many    { $_[0]->kind eq 'has_many'    }
sub is_many_to_many{ $_[0]->kind eq 'many_to_many'}

sub effective_label {
    my ($self) = @_;
    return $self->label if defined($self->label) && length($self->label);
    (my $label = $self->target) =~ s/([A-Z])/ $1/g;
    $label =~ s/^\s+//;
    return $label;
}

sub to_hashref {
    my ($self) = @_;
    my %h = (
        kind   => $self->kind,
        name   => $self->name,
        target => $self->target,
    );
    $h{via}         = $self->via         if defined $self->via;
    $h{through}     = $self->through     if defined $self->through;
    $h{label}       = $self->label       if defined $self->label;
    $h{description} = $self->description if $self->description;
    $h{required}    = 1                  if $self->required;
    return \%h;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Model::Relationship - A relationship between two model classes

=head1 ATTRIBUTES

=over 4

=item C<kind> (required) - belongs_to | has_many | many_to_many

=item C<name> (required) - Relationship accessor name

=item C<target> (required) - Target class name

=item C<via> - FK field name (required for belongs_to)

=item C<through> - Join class name (required for many_to_many)

=item C<label> - Human-readable label

=item C<required> - For belongs_to: FK is required

=back

=cut
