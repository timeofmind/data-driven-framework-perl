package DataDriven::Framework::Schema::Parser;

use strict;
use warnings;
use Moo;
use Carp qw(croak confess);
use YAML qw(LoadFile Load);

use DataDriven::Framework::Model;
use DataDriven::Framework::Model::Class;
use DataDriven::Framework::Model::Slot;
use DataDriven::Framework::Model::Relationship;
use DataDriven::Framework::Model::Constraint;
use DataDriven::Framework::Model::Enum;

# Parse one or more YAML files and return a Model object.
# Files can be a single path string, an arrayref of paths, or a YAML string.

sub parse {
    my ($self, @sources) = @_;

    my @documents;
    for my $source (@sources) {
        if (ref($source) eq 'SCALAR') {
            # YAML string reference
            my $doc = Load($$source);
            push @documents, { doc => $doc, source => '(string)' };
        } elsif (-f $source) {
            my $doc = LoadFile($source);
            push @documents, { doc => $doc, source => $source };
        } else {
            croak "Schema::Parser: cannot find file or parse source: $source";
        }
    }

    croak "Schema::Parser: no documents provided" unless @documents;

    # Merge documents: last one wins for top-level keys, classes/enums are merged
    my %merged_classes;
    my %merged_enums;
    my $schema_version    = '1.0.0';
    my $framework_version = '0.01';
    my $description       = '';
    my @source_files;

    for my $entry (@documents) {
        my $doc    = $entry->{doc};
        my $source = $entry->{source};
        push @source_files, $source unless $source eq '(string)';

        croak "Schema::Parser ($source): document must be a hash" unless ref($doc) eq 'HASH';

        $schema_version    = $doc->{schema_version}    if exists $doc->{schema_version};
        $framework_version = $doc->{framework_version} if exists $doc->{framework_version};
        $description       = $doc->{description}       if exists $doc->{description};

        # Merge enums
        if (exists $doc->{enums} && ref($doc->{enums}) eq 'HASH') {
            for my $enum_name (keys %{$doc->{enums}}) {
                $merged_enums{$enum_name} = {
                    name => $enum_name,
                    %{$doc->{enums}{$enum_name}},
                };
            }
        }

        # Merge classes
        if (exists $doc->{classes} && ref($doc->{classes}) eq 'HASH') {
            for my $class_name (keys %{$doc->{classes}}) {
                $merged_classes{$class_name} = {
                    name => $class_name,
                    %{$doc->{classes}{$class_name}},
                };
            }
        }
    }

    my $model = DataDriven::Framework::Model->new(
        schema_version    => $schema_version,
        framework_version => $framework_version,
        description       => $description,
        source_files      => \@source_files,
    );

    # Build enum objects
    for my $name (sort keys %merged_enums) {
        my $enum_def = $merged_enums{$name};
        my $enum = $self->_build_enum($name, $enum_def);
        $model->add_enum($enum);
    }

    # Build class objects
    for my $name (sort keys %merged_classes) {
        my $class_def = $merged_classes{$name};
        my $class = $self->_build_class($name, $class_def, $model);
        $model->add_class($class);
    }

    return $model;
}

sub _build_enum {
    my ($self, $name, $def) = @_;

    my $values = $def->{values}
        or croak "Enum '$name': missing 'values'";
    croak "Enum '$name': values must be a list" unless ref($values) eq 'ARRAY';

    return DataDriven::Framework::Model::Enum->new(
        name        => $name,
        values      => $values,
        default     => $def->{default},
        description => $def->{description} // '',
    );
}

sub _build_class {
    my ($self, $name, $def, $model) = @_;

    my $class = DataDriven::Framework::Model::Class->new(
        name        => $name,
        label       => $def->{label},
        description => $def->{description} // '',
        table       => $def->{table},
        abstract    => $def->{abstract}   ? 1 : 0,
        is_a        => $def->{is_a},
    );

    # Slots
    if (exists $def->{slots} && ref($def->{slots}) eq 'ARRAY') {
        for my $slot_def (@{$def->{slots}}) {
            my $slot = $self->_build_slot($slot_def, $name);
            $class->add_slot($slot);
        }
    }

    # Relationships
    if (exists $def->{relationships} && ref($def->{relationships}) eq 'HASH') {
        my $rels = $def->{relationships};

        # belongs_to
        if (exists $rels->{belongs_to} && ref($rels->{belongs_to}) eq 'ARRAY') {
            for my $rel_def (@{$rels->{belongs_to}}) {
                croak "Class '$name': belongs_to entry missing 'target'" unless $rel_def->{target};
                croak "Class '$name': belongs_to entry for '" . $rel_def->{target} . "' missing 'via'"
                    unless $rel_def->{via};
                my $rel_name = $rel_def->{name} // _derive_rel_name($rel_def->{target});
                my $rel = DataDriven::Framework::Model::Relationship->new(
                    kind        => 'belongs_to',
                    name        => $rel_name,
                    target      => $rel_def->{target},
                    via         => $rel_def->{via},
                    label       => $rel_def->{label},
                    description => $rel_def->{description} // '',
                    required    => $rel_def->{required} ? 1 : 0,
                    owner       => $name,
                );
                $class->add_relationship($rel);
            }
        }

        # has_many
        if (exists $rels->{has_many} && ref($rels->{has_many}) eq 'ARRAY') {
            for my $rel_def (@{$rels->{has_many}}) {
                croak "Class '$name': has_many entry missing 'target'" unless $rel_def->{target};
                # via for has_many is optional in YAML (reverse of belongs_to's FK)
                my $rel_name = $rel_def->{name} // _derive_rel_name_plural($rel_def->{target});
                my $rel = DataDriven::Framework::Model::Relationship->new(
                    kind        => 'has_many',
                    name        => $rel_name,
                    target      => $rel_def->{target},
                    via         => $rel_def->{via},
                    label       => $rel_def->{label},
                    description => $rel_def->{description} // '',
                    owner       => $name,
                );
                $class->add_relationship($rel);
            }
        }

        # many_to_many
        if (exists $rels->{many_to_many} && ref($rels->{many_to_many}) eq 'ARRAY') {
            for my $rel_def (@{$rels->{many_to_many}}) {
                croak "Class '$name': many_to_many entry missing 'target'" unless $rel_def->{target};
                croak "Class '$name': many_to_many entry for '" . $rel_def->{target} . "' missing 'through'"
                    unless $rel_def->{through};
                my $rel_name = $rel_def->{name} // _derive_rel_name_plural($rel_def->{target});
                my $rel = DataDriven::Framework::Model::Relationship->new(
                    kind        => 'many_to_many',
                    name        => $rel_name,
                    target      => $rel_def->{target},
                    via         => $rel_def->{via},
                    through     => $rel_def->{through},
                    label       => $rel_def->{label},
                    description => $rel_def->{description} // '',
                    owner       => $name,
                );
                $class->add_relationship($rel);
            }
        }
    }

    # Constraints
    if (exists $def->{constraints} && ref($def->{constraints}) eq 'HASH') {
        my $cons = $def->{constraints};

        # unique constraints
        if (exists $cons->{unique}) {
            my $unique = $cons->{unique};
            # Can be a flat array of column names (single unique) or array-of-arrays (multiple)
            if (ref($unique) eq 'ARRAY') {
                if (!ref($unique->[0])) {
                    # Single unique constraint: [col1, col2] or [col1]
                    $class->add_constraint(
                        DataDriven::Framework::Model::Constraint->new(
                            kind    => 'unique',
                            columns => $unique,
                            owner   => $name,
                        )
                    );
                } else {
                    # Multiple unique constraints: [[col1], [col2, col3]]
                    for my $cols (@$unique) {
                        $class->add_constraint(
                            DataDriven::Framework::Model::Constraint->new(
                                kind    => 'unique',
                                columns => $cols,
                                owner   => $name,
                            )
                        );
                    }
                }
            }
        }

        # indexes
        if (exists $cons->{indexes} && ref($cons->{indexes}) eq 'ARRAY') {
            for my $idx_def (@{$cons->{indexes}}) {
                my $cols = ref($idx_def) eq 'HASH' ? $idx_def->{columns} : $idx_def;
                croak "Class '$name': index missing columns" unless ref($cols) eq 'ARRAY';
                $class->add_constraint(
                    DataDriven::Framework::Model::Constraint->new(
                        kind    => 'index',
                        name    => ref($idx_def) eq 'HASH' ? $idx_def->{name} : undef,
                        columns => $cols,
                        owner   => $name,
                    )
                );
            }
        }
    }

    return $class;
}

sub _build_slot {
    my ($self, $def, $class_name) = @_;
    croak "Class '$class_name': slot missing 'name'" unless $def->{name};
    croak "Class '$class_name': slot '" . $def->{name} . "' missing 'type'" unless $def->{type};

    return DataDriven::Framework::Model::Slot->new(
        name          => $def->{name},
        type          => $def->{type},
        enum          => $def->{enum},
        required      => $def->{required}      ? 1 : 0,
        default       => $def->{default},
        autogenerated => $def->{autogenerated}  ? 1 : 0,
        read_only     => $def->{read_only}      ? 1 : 0,
        api_read_only => $def->{api_read_only}  ? 1 : 0,
        hidden        => $def->{hidden}         ? 1 : 0,
        label         => $def->{label},
        description   => $def->{description}   // '',
        placeholder   => $def->{placeholder}   // '',
        control_type  => $def->{control_type},
        ui_order      => $def->{ui_order}       // 999,
        ui_group      => $def->{ui_group}       // '',
        min           => $def->{min},
        max           => $def->{max},
        pattern       => $def->{pattern},
        defined_in    => $class_name,
    );
}

# Convert CamelCase to snake_case for relationship names
sub _derive_rel_name {
    my ($target) = @_;
    (my $name = $target) =~ s/([A-Z])/'_'.lc($1)/ge;
    $name =~ s/^_//;
    return $name;
}

sub _derive_rel_name_plural {
    my ($target) = @_;
    my $name = _derive_rel_name($target);
    $name .= 's' unless $name =~ /s$/;
    return $name;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Schema::Parser - Load YAML schema files into a canonical Model

=head1 SYNOPSIS

    use DataDriven::Framework::Schema::Parser;

    my $parser = DataDriven::Framework::Schema::Parser->new;

    # From file(s)
    my $model = $parser->parse('schema/myapp.yaml');
    my $model = $parser->parse('schema/base.yaml', 'schema/extensions.yaml');

    # From YAML string
    my $model = $parser->parse(\$yaml_string);

=head1 DESCRIPTION

The parser loads one or more YAML documents and builds a
L<DataDriven::Framework::Model>. Multiple files are merged: class and enum
definitions are combined, with later files overriding earlier ones for the same
name. Top-level metadata (schema_version, description) comes from the last file
that sets it.

After parsing, run L<DataDriven::Framework::Schema::Resolver> to resolve
inheritance and cross-references, and L<DataDriven::Framework::Schema::Validator>
to check semantic correctness.

=head1 METHODS

=over 4

=item C<parse(@sources)>

Parse one or more sources. Each source can be:

=over 4

=item A file path (string) - loaded with YAML::XS::LoadFile

=item A scalar reference - treated as a YAML string and parsed with YAML::XS::Load

=back

Returns a L<DataDriven::Framework::Model> object.

=back

=cut
