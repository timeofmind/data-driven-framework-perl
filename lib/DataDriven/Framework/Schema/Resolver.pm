package DataDriven::Framework::Schema::Resolver;

use strict;
use warnings;
use Moo;
use Carp qw(croak);

use DataDriven::Framework::Model::Slot;

# Resolve a parsed (but not yet validated) model:
#  - Link parent Class objects
#  - Set table names
#  - Flatten resolved_slots (parent slots + own slots, no duplicates)
#  - Link enum objects into slots
#  - Auto-derive has_many relationships from belongs_to

sub resolve {
    my ($self, $model) = @_;

    # First pass: link parent objects and set table names
    for my $class ($model->classes) {
        if ($class->has_parent) {
            my $parent = $model->class($class->is_a)
                or croak "Class '" . $class->name . "': parent '" . $class->is_a . "' not found";
            $class->parent_class($parent);
        }
        # Set effective table name
        $class->table($class->effective_table) unless defined($class->table) && length($class->table);
    }

    # Second pass: resolve inherited slots
    for my $class ($model->classes_in_dependency_order) {
        $self->_resolve_slots($class, $model);
    }

    # Third pass: link enum objects into slots
    for my $class ($model->classes) {
        for my $slot (@{$class->all_slots}) {
            if ($slot->type eq 'enum' && defined($slot->enum)) {
                my $enum_obj = $model->enum($slot->enum)
                    or croak "Slot '" . $slot->name . "' in class '" . $class->name
                        . "': enum '" . $slot->enum . "' not defined";
                $slot->enum_obj($enum_obj);
            }
        }
    }

    # Fourth pass: auto-generate has_many from belongs_to relationships
    $self->_auto_generate_has_many($model);

    return $model;
}

sub _resolve_slots {
    my ($self, $class, $model) = @_;

    my @resolved;

    if ($class->has_parent && $class->parent_class) {
        my $parent = $class->parent_class;
        # Parent should already be resolved (due to dependency order)
        my @parent_slots = @{$parent->all_slots};
        push @resolved, @parent_slots;
    }

    # Add own slots, skipping any that override parent slots
    my %seen = map { $_->name => 1 } @resolved;
    for my $slot (@{$class->own_slots}) {
        if ($seen{$slot->name}) {
            # Own slot overrides parent slot - replace it
            @resolved = grep { $_->name ne $slot->name } @resolved;
        }
        push @resolved, $slot;
        $seen{$slot->name} = 1;
    }

    $class->resolved_slots(\@resolved);
}

sub _auto_generate_has_many {
    my ($self, $model) = @_;

    for my $class ($model->classes) {
        for my $rel (@{$class->relationships}) {
            next unless $rel->is_belongs_to;

            my $target_class = $model->class($rel->target) or next;

            # Check if target already has a has_many pointing back
            my $already_exists = grep {
                $_->is_has_many && $_->target eq $class->name
            } @{$target_class->relationships};

            next if $already_exists;

            # Auto-generate has_many on the target class
            my $has_many_name = _to_snake_case_plural($class->name);
            my $has_many = DataDriven::Framework::Model::Relationship->new(
                kind    => 'has_many',
                name    => $has_many_name,
                target  => $class->name,
                via     => $rel->via,
                label   => $class->effective_label . 's',
                owner   => $target_class->name,
            );
            $target_class->add_relationship($has_many);
        }
    }
}

sub _to_snake_case_plural {
    my ($name) = @_;
    $name =~ s/([A-Z])/'_'.lc($1)/ge;
    $name =~ s/^_//;
    $name .= 's' unless $name =~ /s$/;
    return $name;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Schema::Resolver - Resolve inheritance and cross-references in a Model

=head1 SYNOPSIS

    use DataDriven::Framework::Schema::Resolver;

    my $resolver = DataDriven::Framework::Schema::Resolver->new;
    $resolver->resolve($model);   # modifies model in place

=head1 DESCRIPTION

After the parser builds the raw model, the resolver performs several passes:

=over 4

=item 1. Links parent Class objects (C<parent_class> attribute)

=item 2. Sets effective table names where not explicitly given

=item 3. Builds C<resolved_slots>: a flattened list of inherited + own slots per class

=item 4. Links enum objects into slot C<enum_obj> attributes

=item 5. Auto-generates C<has_many> relationships on target classes from C<belongs_to>

=back

The resolver modifies the model in place. Run validator after resolver.

=head1 METHODS

=over 4

=item C<resolve($model)>

Resolves the model in place. Returns the model.

=back

=cut
