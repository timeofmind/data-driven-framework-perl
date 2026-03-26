package DataDriven::Framework::Sandbox::Environment;

use strict;
use warnings;
use Moo;
use Carp qw(croak carp);
use POSIX qw(strftime);

use DataDriven::Framework::Runtime::Registry;
use DataDriven::Framework::Generator::SQL;

has schema_sources => (is => 'ro', required => 1);  # arrayref of YAML paths/strings
has dsn            => (is => 'ro', default  => sub { undef });
has db_user        => (is => 'ro', default  => sub { undef });
has db_pass        => (is => 'ro', default  => sub { '' });
has db_options     => (is => 'ro', default  => sub { { RaiseError => 1, AutoCommit => 1 } });
has namespace      => (is => 'ro', default  => sub { 'DataDriven::Sandbox' });
has use_sqlite     => (is => 'ro', default  => sub { 0 });  # use SQLite for lightweight tests

# Internal state
has _registry  => (is => 'rw', default => sub { undef });
has _dbh       => (is => 'rw', default => sub { undef });
has _db_name   => (is => 'rw', default => sub { undef });
has _is_setup  => (is => 'rw', default => sub { 0     });

sub setup {
    my ($self) = @_;
    return $self if $self->_is_setup;

    # Build registry
    my $registry = DataDriven::Framework::Runtime::Registry->from_schema(
        @{$self->schema_sources},
        { namespace => $self->namespace }
    );
    $self->_registry($registry);

    # Connect to DB
    my $dbh = $self->_connect;
    $self->_dbh($dbh);
    $registry->dbh($dbh);

    # Apply schema
    $self->_apply_schema($dbh, $registry->model);

    $self->_is_setup(1);
    return $self;
}

sub teardown {
    my ($self) = @_;
    return unless $self->_is_setup;

    my $dbh = $self->_dbh;
    if ($dbh) {
        if ($self->use_sqlite) {
            # SQLite: just disconnect; in-memory DB is gone
        } elsif ($self->_db_name) {
            eval { $dbh->do("DROP DATABASE IF EXISTS `" . $self->_db_name . "`") };
            carp "teardown: could not drop database: $@" if $@;
        }
        eval { $dbh->disconnect };
    }

    $self->_is_setup(0);
    $self->_dbh(undef);
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->teardown if $self->_is_setup;
}

sub registry { $_[0]->_registry or croak "Sandbox not set up; call setup() first" }
sub dbh      { $_[0]->_dbh      or croak "Sandbox not set up; call setup() first" }

sub _connect {
    my ($self) = @_;

    if ($self->use_sqlite) {
        require DBD::SQLite;
        my $dbh = DBI->connect('dbi:SQLite::memory:', '', '', {
            RaiseError => 1, AutoCommit => 1
        });
        return $dbh;
    }

    require DBI;
    require DBD::mysql;

    # Create a uniquely-named sandbox database
    my $ts      = strftime('%Y%m%d%H%M%S', localtime);
    my $db_name = "ddfw_sandbox_$$\_$ts";
    $self->_db_name($db_name);

    # Connect without database to create it
    my $base_dsn = $self->dsn;
    $base_dsn =~ s/;?database=\w+//i;
    $base_dsn =~ s/;?dbname=\w+//i;

    my $dbh = DBI->connect(
        $base_dsn,
        $self->db_user,
        $self->db_pass,
        $self->db_options,
    ) or croak "Sandbox: cannot connect: $DBI::errstr";

    $dbh->do("CREATE DATABASE `$db_name` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
    $dbh->do("USE `$db_name`");
    return $dbh;
}

sub _apply_schema {
    my ($self, $dbh, $model) = @_;
    my $gen = DataDriven::Framework::Generator::SQL->new(model => $model);
    my $sql = $gen->generate;

    if ($self->use_sqlite) {
        # Simplify SQL for SQLite (strip ENGINE, CHARSET, etc.)
        $sql = $self->_adapt_sql_for_sqlite($sql);
    }

    # Split on semicolons (handles both ";\n" and ";" at end of string)
    my @statements = split /;[ \t]*\n|;[ \t]*$/, $sql;
    for my $stmt (@statements) {
        $stmt =~ s/^\s+|\s+$//g;
        next unless length($stmt) > 5;
        # Strip leading comment lines so CREATE TABLE statements preceded by
        # "-- Class: Foo" comments are not skipped by the /^--/ filter below
        $stmt =~ s/\A([ \t]*--[^\n]*\n)+//;
        $stmt =~ s/^\s+//;
        next unless length($stmt) > 5;
        next if $stmt =~ /^--/;
        next if $stmt =~ /^\/\*/;
        next if $stmt =~ /^\s*$/;
        next if $stmt =~ /^SET\s+/i;   # skip SET statements for SQLite
        eval { $dbh->do($stmt) };
        if ($@) {
            my $err = $@;
            $err =~ s/ at .*//s;  # truncate for readability
            carp "Schema application warning: $err\n  SQL: " . substr($stmt, 0, 100);
        }
    }
}

sub _adapt_sql_for_sqlite {
    my ($self, $sql) = @_;

    # Process line by line, tracking whether we're inside a CREATE TABLE
    my @lines = split /\n/, $sql;
    my @out;
    my $in_create = 0;

    for my $line (@lines) {
        # Track CREATE TABLE boundaries
        $in_create = 1 if $line =~ /CREATE TABLE/i;

        # Skip lines that SQLite doesn't support (no comma stripping here)
        if ($in_create && $line =~ /^\s*(UNIQUE KEY|INDEX\s+`|KEY\s+`|\s*CONSTRAINT\s.*FOREIGN KEY)/i) {
            next;
        }

        # Skip standalone PRIMARY KEY line (redundant with AUTOINCREMENT; no comma stripping)
        if ($in_create && $line =~ /^\s*PRIMARY KEY\s*\(/i) {
            next;
        }

        # End of CREATE TABLE: strip trailing comma from last column before closing paren
        if ($in_create && $line =~ /^\s*\)\s*(ENGINE|\s*;|\s*$)/i) {
            $in_create = 0;
            for my $i (reverse 0..$#out) {
                if ($out[$i] =~ /\S/) { $out[$i] =~ s/,\s*$//; last; }
            }
        }

        # Type and feature substitutions
        $line =~ s/DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP/DEFAULT CURRENT_TIMESTAMP/gi;
        $line =~ s/ENUM\([^)]+\)/TEXT/gi;
        $line =~ s/VARCHAR\(\d+\)/TEXT/gi;
        $line =~ s/\bDATETIME\b/TEXT/gi;
        $line =~ s/\bDATE\b(?!\s*-)/TEXT/gi;
        $line =~ s/TINYINT\(\d+\)/INTEGER/gi;
        $line =~ s/\bINT\b/INTEGER/gi;
        $line =~ s/\bDOUBLE\b/REAL/gi;
        $line =~ s/\bFLOAT\b/REAL/gi;

        # AUTO_INCREMENT column becomes INTEGER PRIMARY KEY AUTOINCREMENT
        $line =~ s/(`\w+`)\s+INTEGER\s+NOT NULL\s+AUTO_INCREMENT/$1 INTEGER PRIMARY KEY AUTOINCREMENT/gi;
        $line =~ s/\bAUTO_INCREMENT\b//gi;

        # Remove MySQL table options from closing line
        $line =~ s/\)\s*ENGINE=\w+.*$/);/gi;
        $line =~ s/\s+ENGINE=\w+[^;]*//gi;
        $line =~ s/\s+DEFAULT CHARSET=\w+//gi;
        $line =~ s/\s+COLLATE=\S+//gi;
        $line =~ s/\s+COMMENT='[^']*'//gi;

        push @out, $line;
    }

    return join("\n", @out);
}

1;

__END__

=head1 NAME

DataDriven::Framework::Sandbox::Environment - Test sandbox for schema-driven tests

=head1 SYNOPSIS

    use DataDriven::Framework::Sandbox::Environment;

    my $env = DataDriven::Framework::Sandbox::Environment->new(
        schema_sources => ['schema/myapp.yaml'],
        dsn            => 'dbi:mysql:host=localhost',
        db_user        => 'test',
        db_pass        => 'test',
    );

    $env->setup;

    my $User = $env->registry->class('User');
    my $u = $User->new(username => 'alice');
    $u->save($env->dbh);

    $env->teardown;   # drops the sandbox database

    # Or use SQLite for lightweight tests (no MySQL needed):
    my $env = DataDriven::Framework::Sandbox::Environment->new(
        schema_sources => ['schema/myapp.yaml'],
        use_sqlite     => 1,
    );

=head1 DESCRIPTION

Manages a temporary database environment for testing:

=over 4

=item 1. Parses and validates the schema

=item 2. Creates a uniquely-named sandbox database (or SQLite in-memory DB)

=item 3. Applies the generated DDL

=item 4. Provides a registry with generated classes

=item 5. Tears down the database on C<teardown()> or when the object is destroyed

=back

=head1 ATTRIBUTES

=over 4

=item C<schema_sources> (required) - Arrayref of YAML file paths or string refs

=item C<dsn> - DBI DSN (e.g., C<dbi:mysql:host=localhost>). Not needed for SQLite.

=item C<db_user>, C<db_pass> - Database credentials

=item C<namespace> - Perl namespace for generated classes (default: C<DataDriven::Sandbox>)

=item C<use_sqlite> - Use SQLite in-memory DB instead of MySQL (default: 0)

=back

=head1 METHODS

=over 4

=item C<setup()>

Set up the sandbox. Idempotent.

=item C<teardown()>

Drop the sandbox database and disconnect. Called automatically on DESTROY.

=item C<registry()>

Returns the L<DataDriven::Framework::Runtime::Registry>.

=item C<dbh()>

Returns the DBI database handle.

=back

=cut
