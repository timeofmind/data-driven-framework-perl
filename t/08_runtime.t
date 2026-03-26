use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin/lib";

use DataDriven::Framework::Runtime::Registry;
use TestUtils qw(simple_schema_yaml);

# Check if we can use SQLite
my $has_sqlite = eval { require DBD::SQLite; 1 };
unless ($has_sqlite) {
    plan skip_all => 'DBD::SQLite not available';
}

# Build registry
my $registry = eval {
    DataDriven::Framework::Runtime::Registry->from_schema(
        simple_schema_yaml(),
        { namespace => 'TestRuntime' }
    );
};
ok($registry, 'Registry created') or diag($@);

# Check class names
my @names = $registry->class_names;
ok(grep { $_ eq 'User' } @names, 'User class in registry');
ok(grep { $_ eq 'Post' } @names, 'Post class in registry');

# Get classes
my $User = eval { $registry->class('User') };
ok($User, 'Got User class');

my $Post = eval { $registry->class('Post') };
ok($Post, 'Got Post class');

# Unknown class
eval { $registry->class('Nonexistent') };
ok($@, 'unknown class dies');

# Create objects
my $u = $User->new(username => 'alice', email => 'alice@example.com', status => 'active');
ok($u, 'User object created');
is($u->username, 'alice', 'username accessor');
is($u->email, 'alice@example.com', 'email accessor');
is($u->status, 'active', 'status accessor (with default)');
ok(!defined($u->id), 'id is undef before save');

# Accessor mutation
$u->username('bob');
is($u->username, 'bob', 'username mutated');

# to_hashref
my $h = $u->to_hashref;
ok($h, 'to_hashref works');
is($h->{username}, 'bob', 'hashref has username');
ok(!exists $h->{id} || !defined($h->{id}), 'id not set yet');

# ---- SQLite integration ----
SKIP: {
    skip 'DBD::SQLite not available', 15 unless $has_sqlite;

    require DBI;
    require DataDriven::Framework::Sandbox::Environment;

    my $env = DataDriven::Framework::Sandbox::Environment->new(
        schema_sources => [simple_schema_yaml()],
        namespace      => 'TestRuntimeSandbox',
        use_sqlite     => 1,
    );
    $env->setup;
    my $dbh = $env->dbh;
    ok($dbh, 'Got sandbox dbh');

    my $SUser = $env->registry->class('User');

    # Save a user
    my $u2 = $SUser->new(username => 'carol', email => 'carol@example.com');
    eval { $u2->save($dbh) };
    ok(!$@, "save didn't die: $@");
    ok(defined($u2->id), 'id set after save');

    # Load by id
    my $loaded = $SUser->load($u2->id, $dbh);
    ok($loaded, 'load by id');
    is($loaded->username, 'carol', 'loaded username');

    # Update
    $loaded->username('dave');
    $loaded->save($dbh);
    my $updated = $SUser->load($u2->id, $dbh);
    is($updated->username, 'dave', 'updated username');

    # load_all
    my @all = $SUser->load_all($dbh);
    is(scalar @all, 1, 'load_all returns 1 user');

    # Save a second user
    my $u3 = $SUser->new(username => 'eve', email => 'eve@example.com');
    $u3->save($dbh);
    @all = $SUser->load_all($dbh);
    is(scalar @all, 2, 'load_all returns 2 users');

    # Delete
    $updated->delete($dbh);
    @all = $SUser->load_all($dbh);
    is(scalar @all, 1, 'load_all returns 1 user after delete');

    # Load nonexistent
    my $none = $SUser->load(9999, $dbh);
    ok(!defined($none), 'load nonexistent returns undef');

    $env->teardown;
}

done_testing;
