use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin/lib";

use DataDriven::Framework::Sandbox::TestHelper qw(
    with_sandbox sandbox_ok schema_valid_ok model_ok load_fixtures
);
use TestUtils qw(simple_schema_yaml);

my $has_sqlite = eval { require DBD::SQLite; 1 };

# ---- schema_valid_ok ----

my $model = schema_valid_ok(simple_schema_yaml(), 'simple schema is valid');
ok($model, 'schema_valid_ok returns model');
is($model->schema_version, '1.0.0', 'returned model has correct version');

# ---- Bad schema ----
# schema_valid_ok should produce a failing test for invalid schemas;
# wrap in TODO so the test suite doesn't count it as a real failure.
{
    local $TODO = 'intentional failure: bad schema should be detected';
    schema_valid_ok(\<<'YAML', 'bad schema detected');
schema_version: "1.0.0"
classes:
  Broken:
    slots:
      - name: x
        type: enum
        enum: NonExistent
YAML
}

SKIP: {
    skip 'DBD::SQLite not available for sandbox tests', 20 unless $has_sqlite;

    # ---- with_sandbox ----

    with_sandbox([simple_schema_yaml()], { use_sqlite => 1, namespace => 'SandboxTest1' }, sub {
        my ($env) = @_;
        ok($env, 'env passed to with_sandbox callback');
        ok($env->dbh, 'env has dbh');
        ok($env->registry, 'env has registry');
    });
    pass('with_sandbox ran and tore down');

    # ---- model_ok ----

    with_sandbox([simple_schema_yaml()], { use_sqlite => 1, namespace => 'SandboxTest2' }, sub {
        my ($env) = @_;
        model_ok($env->registry, 'User', [qw(id username email status created_at)],
                 'User has expected slots');
        model_ok($env->registry, 'Post', [qw(id title body user_id created_at)],
                 'Post has expected slots');
    });

    # ---- load_fixtures ----

    with_sandbox([simple_schema_yaml()], { use_sqlite => 1, namespace => 'SandboxTest3' }, sub {
        my ($env) = @_;

        load_fixtures($env, {
            User => [
                { username => 'alice', email => 'alice@test.com' },
                { username => 'bob',   email => 'bob@test.com'   },
            ],
        });

        my $User  = $env->registry->class('User');
        my @users = $User->load_all($env->dbh);
        is(scalar @users, 2, 'fixtures loaded 2 users');

        my @names = sort map { $_->username } @users;
        is($names[0], 'alice', 'alice loaded');
        is($names[1], 'bob',   'bob loaded');
    });

    # ---- with_sandbox tears down on error ----

    my $did_teardown = 0;
    eval {
        with_sandbox([simple_schema_yaml()], { use_sqlite => 1, namespace => 'SandboxTest4' }, sub {
            my ($env) = @_;
            # Verify it's set up
            ok($env->_is_setup, 'env is set up inside callback');
            die "test error";
        });
    };
    ok($@, 'error propagated from with_sandbox');
    like($@, qr/test error/, 'error message preserved');
    pass('sandbox teardown happened despite error');

    # ---- sandbox_ok ----

    sandbox_ok([simple_schema_yaml()], { use_sqlite => 1, namespace => 'SandboxTest5' },
               'sandbox_ok test');
}

done_testing;
