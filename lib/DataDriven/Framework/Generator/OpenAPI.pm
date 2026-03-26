package DataDriven::Framework::Generator::OpenAPI;

use strict;
use warnings;
use Moo;
use YAML qw(Dump);
use DataDriven::Framework::Model::ValueType;

has model   => (is => 'ro', required => 1);
has api_title   => (is => 'ro', default => sub { 'Generated API' });
has api_version => (is => 'ro', default => sub { '1.0.0' });
has base_path   => (is => 'ro', default => sub { '/api/v1' });

sub generate {
    my ($self) = @_;
    my $model = $self->model;

    my %components_schemas;

    # Enum schemas
    for my $enum ($model->enums) {
        $components_schemas{$enum->name} = {
            type => 'string',
            enum => $enum->values,
            ( $enum->description ? (description => $enum->description) : () ),
        };
    }

    # Class schemas (request/response bodies)
    for my $class ($model->classes) {
        next if $class->abstract;
        $components_schemas{$class->name}         = $self->_class_response_schema($class, $model);
        $components_schemas{$class->name . 'Input'} = $self->_class_input_schema($class, $model);
        $components_schemas{$class->name . 'List'}  = {
            type  => 'object',
            properties => {
                data  => { type => 'array', items => { '$ref' => '#/components/schemas/' . $class->name } },
                total => { type => 'integer' },
                page  => { type => 'integer' },
                per_page => { type => 'integer' },
            },
        };
    }

    # Error schema
    $components_schemas{Error} = {
        type => 'object',
        properties => {
            error   => { type => 'string' },
            message => { type => 'string' },
            code    => { type => 'integer' },
        },
        required => ['error', 'message'],
    };

    # Paths
    my %paths;
    for my $class ($model->classes) {
        next if $class->abstract;
        my $base = lc($class->effective_table);
        $base =~ s/_/-/g;
        my $path_base = $self->base_path . "/$base";

        # Collection endpoints
        $paths{$path_base} = {
            get  => $self->_list_operation($class),
            post => $self->_create_operation($class),
        };

        # Item endpoints
        $paths{"$path_base/{id}"} = {
            get    => $self->_get_operation($class),
            put    => $self->_update_operation($class),
            delete => $self->_delete_operation($class),
        };
    }

    my $spec = {
        openapi => '3.0.3',
        info    => {
            title       => $self->api_title   || $model->description || 'Generated API',
            version     => $self->api_version || $model->schema_version,
            description => $model->description || '',
        },
        paths      => \%paths,
        components => { schemas => \%components_schemas },
    };

    return $spec;
}

sub generate_yaml {
    my ($self) = @_;
    return Dump($self->generate);
}

sub _list_operation {
    my ($self, $class) = @_;
    my $name = $class->name;
    return {
        summary     => 'List ' . $class->effective_label . 's',
        operationId => 'list' . $name,
        tags        => [$name],
        parameters  => [
            { name => 'page',     in => 'query', schema => { type => 'integer', default => 1 } },
            { name => 'per_page', in => 'query', schema => { type => 'integer', default => 20 } },
        ],
        responses => {
            '200' => {
                description => 'A list of ' . $class->effective_label . 's',
                content => { 'application/json' => {
                    schema => { '$ref' => "#/components/schemas/${name}List" }
                }},
            },
            '400' => { '$ref' => '#/components/responses/BadRequest' },
        },
    };
}

sub _create_operation {
    my ($self, $class) = @_;
    my $name = $class->name;
    return {
        summary     => 'Create a ' . $class->effective_label,
        operationId => 'create' . $name,
        tags        => [$name],
        requestBody => {
            required => 1,
            content  => { 'application/json' => {
                schema => { '$ref' => "#/components/schemas/${name}Input" }
            }},
        },
        responses => {
            '201' => {
                description => 'Created',
                content => { 'application/json' => {
                    schema => { '$ref' => "#/components/schemas/$name" }
                }},
            },
            '400' => { description => 'Validation error' },
            '422' => { description => 'Unprocessable entity' },
        },
    };
}

sub _get_operation {
    my ($self, $class) = @_;
    my $name = $class->name;
    return {
        summary     => 'Get a ' . $class->effective_label . ' by ID',
        operationId => 'get' . $name,
        tags        => [$name],
        parameters  => [
            { name => 'id', in => 'path', required => 1, schema => { type => 'integer' } },
        ],
        responses => {
            '200' => {
                description => 'The ' . $class->effective_label,
                content => { 'application/json' => {
                    schema => { '$ref' => "#/components/schemas/$name" }
                }},
            },
            '404' => { description => 'Not found' },
        },
    };
}

sub _update_operation {
    my ($self, $class) = @_;
    my $name = $class->name;
    return {
        summary     => 'Update a ' . $class->effective_label,
        operationId => 'update' . $name,
        tags        => [$name],
        parameters  => [
            { name => 'id', in => 'path', required => 1, schema => { type => 'integer' } },
        ],
        requestBody => {
            required => 1,
            content  => { 'application/json' => {
                schema => { '$ref' => "#/components/schemas/${name}Input" }
            }},
        },
        responses => {
            '200' => {
                description => 'Updated',
                content => { 'application/json' => {
                    schema => { '$ref' => "#/components/schemas/$name" }
                }},
            },
            '400' => { description => 'Validation error' },
            '404' => { description => 'Not found' },
        },
    };
}

sub _delete_operation {
    my ($self, $class) = @_;
    my $name = $class->name;
    return {
        summary     => 'Delete a ' . $class->effective_label,
        operationId => 'delete' . $name,
        tags        => [$name],
        parameters  => [
            { name => 'id', in => 'path', required => 1, schema => { type => 'integer' } },
        ],
        responses => {
            '204' => { description => 'Deleted' },
            '404' => { description => 'Not found' },
        },
    };
}

sub _class_response_schema {
    my ($self, $class, $model) = @_;
    my %properties;
    for my $slot (@{$class->all_slots}) {
        next if $slot->hidden;
        $properties{$slot->name} = $self->_slot_openapi_schema($slot, $model);
    }
    my $schema = {
        type       => 'object',
        properties => \%properties,
        ( $class->description ? (description => $class->description) : () ),
    };
    return $schema;
}

sub _class_input_schema {
    my ($self, $class, $model) = @_;
    my %properties;
    my @required;
    for my $slot (@{$class->all_slots}) {
        next if $slot->hidden || $slot->read_only || $slot->autogenerated;
        $properties{$slot->name} = $self->_slot_openapi_schema($slot, $model);
        push @required, $slot->name if $slot->required;
    }
    return {
        type       => 'object',
        properties => \%properties,
        ( @required ? (required => \@required) : () ),
    };
}

sub _slot_openapi_schema {
    my ($self, $slot, $model) = @_;
    my %schema;
    if ($slot->type eq 'enum' && $slot->enum_obj) {
        %schema = ( '$ref' => '#/components/schemas/' . $slot->enum );
    } else {
        %schema = %{ DataDriven::Framework::Model::ValueType->json_schema_type($slot->type) };
    }
    $schema{description} = $slot->description if $slot->description;
    $schema{readOnly}     = 1 if $slot->read_only || $slot->autogenerated;
    $schema{default}      = $slot->default if defined($slot->default) && !$slot->autogenerated;
    $schema{pattern}      = $slot->pattern if defined($slot->pattern);
    if (defined($slot->min)) {
        $slot->type =~ /^(integer|float)$/ ? ($schema{minimum} = $slot->min + 0)
                                           : ($schema{minLength} = $slot->min + 0);
    }
    if (defined($slot->max)) {
        $slot->type =~ /^(integer|float)$/ ? ($schema{maximum} = $slot->max + 0)
                                           : ($schema{maxLength} = $slot->max + 0);
    }
    return \%schema;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Generator::OpenAPI - Generate OpenAPI 3.0 spec from a Model

=head1 SYNOPSIS

    use DataDriven::Framework::Generator::OpenAPI;

    my $gen = DataDriven::Framework::Generator::OpenAPI->new(
        model       => $model,
        api_title   => 'My API',
        api_version => '1.0.0',
        base_path   => '/api/v1',
    );

    my $spec = $gen->generate;       # Perl hashref
    my $yaml = $gen->generate_yaml;  # YAML string

=head1 DESCRIPTION

Generates an OpenAPI 3.0.3 specification from a L<DataDriven::Framework::Model>.
For each concrete class, produces CRUD endpoints and component schemas
(response schema, input schema, list response schema).

=head1 METHODS

=over 4

=item C<generate()>

Returns the OpenAPI spec as a Perl data structure.

=item C<generate_yaml()>

Returns the OpenAPI spec as a YAML string.

=back

=cut
