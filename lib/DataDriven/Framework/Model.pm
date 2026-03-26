package DataDriven::Framework::Model;

use strict;
use warnings;
use Moo;
use Carp qw(croak);
use Digest::MD5 qw(md5_hex);
use YAML qw(Dump);

has schema_version    => (is => 'ro', default => sub { '1.0.0' });
has framework_version => (is => 'ro', default => sub { '0.01'  });
has description       => (is => 'ro', default => sub { ''      });
has source_files      => (is => 'ro', default => sub { []      });  # paths of YAML files

# Main registries
has _classes => (is => 'ro', default => sub { {} });  # name -> Class object
has _enums   => (is => 'ro', default => sub { {} });  # name -> Enum object

sub add_class {
    my ($self, $class) = @_;
    croak "Duplicate class '" . $class->name . "'" if exists $self->_classes->{$class->name};
    $self->_classes->{$class->name} = $class;
}

sub add_enum {
    my ($self, $enum) = @_;
    croak "Duplicate enum '" . $enum->name . "'" if exists $self->_enums->{$enum->name};
    $self->_enums->{$enum->name} = $enum;
}

sub class {
    my ($self, $name) = @_;
    return $self->_classes->{$name};
}

sub enum {
    my ($self, $name) = @_;
    return $self->_enums->{$name};
}

sub classes {
    my ($self) = @_;
    return values %{$self->_classes};
}

sub class_names {
    my ($self) = @_;
    return sort keys %{$self->_classes};
}

sub enums {
    my ($self) = @_;
    return values %{$self->_enums};
}

sub enum_names {
    my ($self) = @_;
    return sort keys %{$self->_enums};
}

sub has_class {
    my ($self, $name) = @_;
    return exists $self->_classes->{$name};
}

sub has_enum {
    my ($self, $name) = @_;
    return exists $self->_enums->{$name};
}

# Topological sort of classes: parents before children
sub classes_in_dependency_order {
    my ($self) = @_;
    my %visited;
    my @ordered;
    my %classes = %{$self->_classes};

    my $visit;
    $visit = sub {
        my ($name) = @_;
        return if $visited{$name};
        $visited{$name} = 1;
        my $class = $classes{$name} or croak "Unknown class '$name'";
        if ($class->has_parent) {
            $visit->($class->is_a);
        }
        push @ordered, $class;
    };

    $visit->($_) for sort keys %classes;
    return @ordered;
}

# Concrete (non-abstract) classes
sub concrete_classes {
    my ($self) = @_;
    return grep { !$_->abstract } $self->classes_in_dependency_order;
}

# Compute a stable hash of the model for change detection
sub model_hash {
    my ($self) = @_;
    my @parts;
    push @parts, "schema_version=" . $self->schema_version;
    for my $name ($self->class_names) {
        my $class = $self->class($name);
        push @parts, "class=$name";
        push @parts, "table=" . $class->effective_table;
        for my $slot (@{$class->slots}) {
            push @parts, "slot=" . $slot->name . "/" . $slot->type;
        }
    }
    for my $name ($self->enum_names) {
        my $enum = $self->enum($name);
        push @parts, "enum=$name:" . join(',', @{$enum->values});
    }
    return md5_hex(join("\n", @parts));
}

1;

__END__

=head1 NAME

DataDriven::Framework::Model - The canonical in-memory model built from YAML schema files

=head1 SYNOPSIS

    use DataDriven::Framework::Model;

    my $model = DataDriven::Framework::Model->new(
        schema_version => '1.2.0',
        description    => 'My application schema',
    );
    $model->add_class($class_obj);
    $model->add_enum($enum_obj);

    my @classes = $model->classes_in_dependency_order;

=head1 DESCRIPTION

The Model is the central data structure of the framework. It holds all class and
enum definitions and is the input to every generator. It is produced by
L<DataDriven::Framework::Schema::Parser> and refined by
L<DataDriven::Framework::Schema::Resolver>.

=head1 METHODS

=over 4

=item C<add_class($class)>, C<add_enum($enum)>

Register a class or enum. Croaks on duplicate name.

=item C<class($name)>, C<enum($name)>

Look up a class or enum by name. Returns undef if not found.

=item C<classes()>, C<enums()>

Return all registered objects (unordered).

=item C<class_names()>, C<enum_names()>

Return sorted lists of names.

=item C<classes_in_dependency_order()>

Return classes topologically sorted so parents appear before children.

=item C<concrete_classes()>

Return non-abstract classes in dependency order.

=item C<model_hash()>

Return an MD5 hex digest of the model's content, suitable for change detection.

=back

=cut
