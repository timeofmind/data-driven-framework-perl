package DataDriven::Framework::Sandbox::TestHelper;

use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak carp);
use Test::More ();

use DataDriven::Framework::Sandbox::Environment;
use DataDriven::Framework::Sandbox::Fixtures;

our @EXPORT_OK = qw(
    with_sandbox
    sandbox_ok
    load_fixtures
    model_ok
    schema_valid_ok
);

# Run a test block with a fully set-up sandbox environment.
# Tears down automatically after the block (or on error).
#
#   with_sandbox(['schema/myapp.yaml'], sub { my ($env) = @_; ... });
#   with_sandbox(['schema/myapp.yaml'], { use_sqlite => 1 }, sub { ... });
sub with_sandbox {
    my $code = pop @_;
    my @sources = ref($_[0]) eq 'ARRAY' ? @{$_[0]} : ($_[0]);
    my %opts    = ref($_[1]) eq 'HASH'  ? %{$_[1]} : ();

    croak "with_sandbox: last argument must be a coderef" unless ref($code) eq 'CODE';

    my $env = DataDriven::Framework::Sandbox::Environment->new(
        schema_sources => \@sources,
        %opts,
    );

    eval {
        $env->setup;
        $code->($env);
    };
    my $err = $@;
    eval { $env->teardown };
    die $err if $err;
}

# Test::More-compatible assertion: sandbox sets up without error
sub sandbox_ok {
    my ($sources, $opts, $test_name) = @_;
    if (ref($opts) ne 'HASH') {
        $test_name = $opts;
        $opts = {};
    }
    $sources = [$sources] unless ref($sources) eq 'ARRAY';
    $test_name //= 'sandbox setup ok';

    my $env = DataDriven::Framework::Sandbox::Environment->new(
        schema_sources => $sources,
        %$opts,
    );
    my $ok = eval { $env->setup; 1 };
    my $err = $@;
    eval { $env->teardown };

    Test::More::ok($ok, $test_name);
    Test::More::diag("Error: $err") if !$ok && $err;
    return $ok ? $env : undef;
}

# Load fixtures inside a with_sandbox block
sub load_fixtures {
    my ($env, $data_or_path) = @_;
    my $f = DataDriven::Framework::Sandbox::Fixtures->new(environment => $env);
    if (ref($data_or_path) eq 'HASH') {
        $f->load_data($data_or_path);
    } else {
        $f->load_file($data_or_path);
    }
    return $f;
}

# Assert that a model class has the expected slots
sub model_ok {
    my ($registry, $class_name, $expected_slots, $test_name) = @_;
    $test_name //= "model class '$class_name' ok";

    my $perl_class = eval { $registry->class($class_name) };
    unless ($perl_class) {
        Test::More::fail("$test_name: class '$class_name' not found");
        return;
    }

    my $mc = $perl_class->_model_class;
    my %actual = map { $_->name => 1 } @{$mc->all_slots};
    my @missing = grep { !$actual{$_} } @$expected_slots;

    if (@missing) {
        Test::More::fail("$test_name: missing slots: " . join(', ', @missing));
    } else {
        Test::More::pass($test_name);
    }
}

# Assert that a schema file parses and validates without errors
sub schema_valid_ok {
    my ($source, $test_name) = @_;
    $test_name //= "schema is valid";

    require DataDriven::Framework::Schema::Parser;
    require DataDriven::Framework::Schema::Resolver;
    require DataDriven::Framework::Schema::Validator;

    my $sources = ref($source) eq 'ARRAY' ? $source : [$source];
    my ($model, @errors);

    eval {
        my $parser = DataDriven::Framework::Schema::Parser->new;
        $model = $parser->parse(@$sources);
        my $resolver = DataDriven::Framework::Schema::Resolver->new;
        $resolver->resolve($model);
        my $validator = DataDriven::Framework::Schema::Validator->new;
        @errors = $validator->validate($model);
    };
    my $parse_err = $@;

    if ($parse_err) {
        Test::More::fail("$test_name: $parse_err");
        return;
    }
    if (@errors) {
        Test::More::fail("$test_name:\n" . join("\n", map { "  $_" } @errors));
        return;
    }

    Test::More::pass($test_name);
    return $model;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Sandbox::TestHelper - Test::More helpers for schema-driven tests

=head1 SYNOPSIS

    use Test::More;
    use DataDriven::Framework::Sandbox::TestHelper qw(
        with_sandbox schema_valid_ok model_ok load_fixtures
    );

    schema_valid_ok('schema/myapp.yaml');

    with_sandbox(['schema/myapp.yaml'], { use_sqlite => 1 }, sub {
        my ($env) = @_;

        model_ok($env->registry, 'User', ['id', 'username', 'status']);

        load_fixtures($env, {
            User => [{ username => 'alice', status => 'active' }],
        });

        my $User = $env->registry->class('User');
        my @users = $User->load_all($env->dbh);
        is(scalar @users, 1, 'one user loaded');
    });

    done_testing;

=head1 EXPORTED FUNCTIONS

=over 4

=item C<with_sandbox(\@sources, \%opts, $coderef)>

Run C<$coderef> with a set-up sandbox environment. Tears down automatically.

=item C<sandbox_ok(\@sources, \%opts, $test_name)>

Assert that the sandbox sets up without error.

=item C<load_fixtures($env, $data_or_path)>

Load fixture data (hashref or file path) into the sandbox.

=item C<model_ok($registry, $class_name, \@slots, $test_name)>

Assert that a class has all the expected slots.

=item C<schema_valid_ok($source, $test_name)>

Assert that a schema file(s) parse and validate correctly.

=back

=cut
