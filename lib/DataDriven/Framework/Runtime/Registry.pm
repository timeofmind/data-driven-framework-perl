package DataDriven::Framework::Runtime::Registry;

use strict;
use warnings;
use Moo;
use Carp qw(croak);

use DataDriven::Framework::Schema::Parser;
use DataDriven::Framework::Schema::Resolver;
use DataDriven::Framework::Schema::Validator;
use DataDriven::Framework::Runtime::ClassGenerator;

has model     => (is => 'ro', required => 1);
has namespace => (is => 'ro', default  => sub { 'DataDriven::Generated' });
has dbh       => (is => 'rw', default  => sub { undef });   # optional shared DBI handle

has _classes  => (is => 'ro', default  => sub { {} });     # model_name -> perl_pkg
has _generator => (is => 'lazy');

sub _build__generator {
    my ($self) = @_;
    return DataDriven::Framework::Runtime::ClassGenerator->new(
        registry  => $self,
        namespace => $self->namespace,
    );
}

# Build registry from schema file(s)
sub from_schema {
    my ($class, @sources) = @_;
    my %opts;
    %opts = %{pop @sources} if ref($sources[-1]) eq 'HASH';

    my $parser   = DataDriven::Framework::Schema::Parser->new;
    my $model    = $parser->parse(@sources);
    my $resolver = DataDriven::Framework::Schema::Resolver->new;
    $resolver->resolve($model);
    my $validator = DataDriven::Framework::Schema::Validator->new;
    $validator->validate_or_die($model);

    my $self = $class->new(model => $model, %opts);
    $self->_build_classes;
    return $self;
}

sub _build_classes {
    my ($self) = @_;
    my %generated = $self->_generator->generate_all;
    for my $name (keys %generated) {
        $self->_classes->{$name} = $generated{$name};
    }
}

# Get the Perl class for a model class name
sub class {
    my ($self, $name) = @_;
    my $pkg = $self->_classes->{$name};
    croak "Registry: no class '$name' (is it abstract or not in schema?)" unless defined $pkg;
    return $pkg;
}

# List all class names
sub class_names {
    my ($self) = @_;
    return sort keys %{$self->_classes};
}

# Connect a DBI handle and store it
sub connect {
    my ($self, @dbi_args) = @_;
    require DBI;
    $self->dbh(DBI->connect(@dbi_args));
    return $self;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Runtime::Registry - Central hub for runtime model access

=head1 SYNOPSIS

    use DataDriven::Framework::Runtime::Registry;

    # Load schema and generate classes
    my $registry = DataDriven::Framework::Runtime::Registry->from_schema(
        'schema/myapp.yaml',
        { namespace => 'MyApp::Model' }
    );

    # Connect to database
    $registry->connect("dbi:mysql:database=mydb", $user, $pass, { RaiseError => 1 });

    # Use generated classes
    my $User = $registry->class('User');
    my $u = $User->new(username => 'alice');
    $u->save($registry->dbh);

    my $loaded = $User->load(1, $registry->dbh);
    print $loaded->username;

=head1 DESCRIPTION

The Registry is the entry point for the runtime layer. It:

=over 4

=item 1. Parses and validates the schema

=item 2. Generates Perl classes dynamically

=item 3. Holds a shared DBI handle (optional)

=back

=head1 CLASS METHODS

=over 4

=item C<from_schema(@sources, \%opts)>

Parse the schema, validate it, resolve inheritance, and generate classes.
C<\%opts> is an optional trailing hashref; currently supports C<namespace>
and C<dbh>.

=back

=head1 INSTANCE METHODS

=over 4

=item C<class($name)>

Returns the Perl package for the named model class.

=item C<class_names()>

Returns a sorted list of all generated class names.

=item C<connect(@dbi_args)>

Connect to a database and store the handle.

=item C<dbh()>

Returns the shared DBI handle, or undef if not connected.

=back

=cut
