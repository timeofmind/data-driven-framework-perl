package DataDriven::Framework::Sandbox::Fixtures;

use strict;
use warnings;
use Moo;
use Carp qw(croak carp);
use YAML qw(LoadFile Load);
use JSON::PP qw(decode_json);

has environment => (is => 'ro', required => 1);  # Sandbox::Environment object

# Load fixtures from one or more files (YAML or JSON)
sub load_file {
    my ($self, @paths) = @_;
    for my $path (@paths) {
        my $data;
        if ($path =~ /\.ya?ml$/i) {
            $data = LoadFile($path);
        } elsif ($path =~ /\.json$/i) {
            open my $fh, '<', $path or croak "Cannot open $path: $!";
            my $json = do { local $/; <$fh> };
            close $fh;
            $data = decode_json($json);
        } else {
            croak "Fixtures: unrecognized file format for $path (expected .yaml or .json)";
        }
        $self->load_data($data);
    }
}

# Load fixtures from a Perl data structure:
#   { ClassName => [ {field => val, ...}, ... ], ... }
sub load_data {
    my ($self, $data) = @_;
    croak "Fixtures: data must be a hashref" unless ref($data) eq 'HASH';

    my $registry = $self->environment->registry;
    my $dbh      = $self->environment->dbh;

    for my $class_name (sort keys %$data) {
        my $perl_class = eval { $registry->class($class_name) };
        unless ($perl_class) {
            carp "Fixtures: unknown class '$class_name', skipping";
            next;
        }

        my $records = $data->{$class_name};
        croak "Fixtures: records for '$class_name' must be an arrayref"
            unless ref($records) eq 'ARRAY';

        for my $record (@$records) {
            my $obj = $perl_class->new(%$record);
            $obj->save($dbh);
        }
    }
}

# Clear all data from all tables (in reverse dependency order)
sub clear_all {
    my ($self) = @_;
    my $dbh   = $self->environment->dbh;
    my $model = $self->environment->registry->model;

    $dbh->do("SET FOREIGN_KEY_CHECKS = 0") if !$self->environment->use_sqlite;

    for my $class (reverse $model->classes_in_dependency_order) {
        next if $class->abstract;
        my $table = $class->effective_table;
        eval { $dbh->do("DELETE FROM `$table`") };
    }

    $dbh->do("SET FOREIGN_KEY_CHECKS = 1") if !$self->environment->use_sqlite;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Sandbox::Fixtures - Load test fixture data into a sandbox

=head1 SYNOPSIS

    use DataDriven::Framework::Sandbox::Fixtures;

    my $fixtures = DataDriven::Framework::Sandbox::Fixtures->new(
        environment => $env,
    );

    # From YAML file:
    # DeviceClass:
    #   - name: Routers
    #   - name: Switches
    $fixtures->load_file('t/fixtures/seed.yaml');

    # From Perl data structure:
    $fixtures->load_data({
        DeviceClass => [
            { name => 'Routers' },
            { name => 'Switches' },
        ],
    });

    # Clear all data
    $fixtures->clear_all;

=head1 DESCRIPTION

Loads test fixture data into a sandbox database using the generated model classes.
Supports YAML and JSON fixture files.

Fixture files have the structure:

    ClassName:
      - field1: value1
        field2: value2
      - field1: value3
        field2: value4

=head1 METHODS

=over 4

=item C<load_file(@paths)>

Load fixture data from YAML or JSON files.

=item C<load_data($hashref)>

Load fixture data from a Perl hashref.

=item C<clear_all()>

Delete all records from all tables (respects foreign key order).

=back

=cut
