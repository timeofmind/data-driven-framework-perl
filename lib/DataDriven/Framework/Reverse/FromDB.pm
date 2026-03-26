package DataDriven::Framework::Reverse::FromDB;

use strict;
use warnings;
use Moo;
use Carp qw(croak);
use YAML qw(Dump);
use DataDriven::Framework::Model::ValueType;

has dbh     => (is => 'ro', required => 1);   # DBI database handle
has schema  => (is => 'ro', default  => sub { undef });  # MySQL schema/database name

# Introspect the database and return a YAML schema string.
sub generate_yaml {
    my ($self) = @_;
    my $data = $self->introspect;
    return Dump($data);
}

# Returns a Perl data structure matching the YAML schema format.
sub introspect {
    my ($self) = @_;
    my $dbh = $self->dbh;

    my $schema_name = $self->schema // $self->_current_schema;

    my @tables = $self->_list_tables($schema_name);
    my %classes;

    for my $table (@tables) {
        # Skip framework metadata tables
        next if $table =~ /^_framework_/;

        my @columns = $self->_table_columns($schema_name, $table);
        my @fks      = $self->_table_foreign_keys($schema_name, $table);
        my @indexes  = $self->_table_indexes($schema_name, $table);

        my %fk_cols = map { $_->{column} => $_ } @fks;

        my $class_name = _table_to_class_name($table);
        my @slots;
        for my $col (@columns) {
            my $slot = $self->_column_to_slot($col, \%fk_cols);
            push @slots, $slot;
        }

        # Relationships from FKs
        my @belongs_to;
        for my $fk (@fks) {
            push @belongs_to, {
                target => _table_to_class_name($fk->{ref_table}),
                via    => $fk->{column},
                label  => "# reverse-generated",
            };
        }

        # Constraints from unique indexes
        my @unique_constraints;
        my @extra_indexes;
        for my $idx (@indexes) {
            next if $idx->{name} eq 'PRIMARY';
            if ($idx->{unique}) {
                push @unique_constraints, $idx->{columns};
            } else {
                push @extra_indexes, { columns => $idx->{columns} };
            }
        }

        my %class_def = (
            label       => _table_to_label($table),
            description => "# reverse-generated from table $table",
            table       => $table,
            slots       => \@slots,
        );
        $class_def{relationships}{belongs_to} = \@belongs_to if @belongs_to;
        if (@unique_constraints) {
            $class_def{constraints}{unique} = @unique_constraints == 1
                ? $unique_constraints[0]
                : \@unique_constraints;
        }
        $class_def{constraints}{indexes} = \@extra_indexes if @extra_indexes;

        $classes{$class_name} = \%class_def;
    }

    return {
        schema_version    => '1.0.0',
        framework_version => '0.01',
        description       => "# reverse-generated from database $schema_name",
        classes           => \%classes,
    };
}

sub _current_schema {
    my ($self) = @_;
    my ($name) = $self->dbh->selectrow_array('SELECT DATABASE()');
    return $name // croak "Cannot determine current database; use 'schema' attribute";
}

sub _list_tables {
    my ($self, $schema) = @_;
    my $rows = $self->dbh->selectall_arrayref(
        "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'BASE TABLE'
         ORDER BY TABLE_NAME",
        {}, $schema
    );
    return map { $_->[0] } @$rows;
}

sub _table_columns {
    my ($self, $schema, $table) = @_;
    my $rows = $self->dbh->selectall_arrayref(
        "SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE,
                COLUMN_DEFAULT, EXTRA, COLUMN_COMMENT, CHARACTER_MAXIMUM_LENGTH,
                NUMERIC_PRECISION, ORDINAL_POSITION
         FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
         ORDER BY ORDINAL_POSITION",
        { Slice => {} }, $schema, $table
    );
    return @$rows;
}

sub _table_foreign_keys {
    my ($self, $schema, $table) = @_;
    my $rows = $self->dbh->selectall_arrayref(
        "SELECT kcu.COLUMN_NAME, kcu.REFERENCED_TABLE_NAME, kcu.REFERENCED_COLUMN_NAME
         FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
         JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
           ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
           AND tc.TABLE_SCHEMA = kcu.TABLE_SCHEMA
           AND tc.TABLE_NAME = kcu.TABLE_NAME
         WHERE kcu.TABLE_SCHEMA = ? AND kcu.TABLE_NAME = ?
           AND tc.CONSTRAINT_TYPE = 'FOREIGN KEY'",
        { Slice => {} }, $schema, $table
    );
    return map { {
        column      => $_->{COLUMN_NAME},
        ref_table   => $_->{REFERENCED_TABLE_NAME},
        ref_column  => $_->{REFERENCED_COLUMN_NAME},
    } } @$rows;
}

sub _table_indexes {
    my ($self, $schema, $table) = @_;
    my $rows = $self->dbh->selectall_arrayref(
        "SELECT INDEX_NAME, NON_UNIQUE, COLUMN_NAME, SEQ_IN_INDEX
         FROM INFORMATION_SCHEMA.STATISTICS
         WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
         ORDER BY INDEX_NAME, SEQ_IN_INDEX",
        { Slice => {} }, $schema, $table
    );
    my %indexes;
    for my $row (@$rows) {
        my $iname = $row->{INDEX_NAME};
        $indexes{$iname} //= { name => $iname, unique => !$row->{NON_UNIQUE}, columns => [] };
        push @{$indexes{$iname}{columns}}, $row->{COLUMN_NAME};
    }
    return values %indexes;
}

sub _column_to_slot {
    my ($self, $col, $fk_cols) = @_;

    my $name    = $col->{COLUMN_NAME};
    my $type    = DataDriven::Framework::Model::ValueType->from_mysql_type($col->{DATA_TYPE});
    my $null    = ($col->{IS_NULLABLE} // 'YES') eq 'YES';
    my $extra   = $col->{EXTRA} // '';
    my $default = $col->{COLUMN_DEFAULT};
    my $comment = $col->{COLUMN_COMMENT} // '';

    my %slot = (
        name  => $name,
        type  => $type,
    );

    $slot{required}      = 1 if !$null && !($extra =~ /auto_increment/i);
    $slot{autogenerated} = 1 if $extra =~ /auto_increment/i || $default =~ /CURRENT_TIMESTAMP/i;
    $slot{read_only}     = 1 if $extra =~ /auto_increment/i;
    $slot{default}       = $default if defined($default) && $default !~ /CURRENT_TIMESTAMP/i;
    $slot{description}   = $comment if $comment;
    $slot{hidden}        = 1 if exists $fk_cols->{$name};  # FK cols are typically hidden in UI

    return \%slot;
}

sub _table_to_class_name {
    my ($table) = @_;
    $table =~ s/_(\w)/uc($1)/ge;
    return ucfirst($table);
}

sub _table_to_label {
    my ($table) = @_;
    (my $label = $table) =~ s/_/ /g;
    $label =~ s/\b(\w)/uc($1)/ge;
    $label =~ s/s$// if $label =~ /s$/;  # naive depluralize
    return $label;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Reverse::FromDB - Generate YAML schema from an existing MySQL database

=head1 SYNOPSIS

    use DBI;
    use DataDriven::Framework::Reverse::FromDB;

    my $dbh = DBI->connect("dbi:mysql:database=mydb", $user, $pass, { RaiseError => 1 });
    my $rev = DataDriven::Framework::Reverse::FromDB->new(dbh => $dbh);

    print $rev->generate_yaml;

=head1 DESCRIPTION

Introspects an existing MySQL database using C<INFORMATION_SCHEMA> and generates
a starter YAML schema file. The output is intended as a starting point and will
need manual review and refinement.

=head2 What is recovered

=over 4

=item * Tables → classes

=item * Columns → slots with best-effort type mapping

=item * Foreign keys → belongs_to relationships

=item * Unique indexes → unique constraints

=item * Nullable/non-nullable → required attribute

=item * AUTO_INCREMENT → autogenerated + read_only

=back

=head2 What is not recovered

=over 4

=item * Enum values (MySQL ENUM types are detected but values may need to be extracted manually)

=item * UI metadata (labels, ui_order, control_type, etc.)

=item * Documentation strings (column comments are imported)

=item * Inheritance structure

=back

Reverse-generated elements are annotated with C<# reverse-generated> comments.

=head1 ATTRIBUTES

=over 4

=item C<dbh> (required) - A connected DBI database handle

=item C<schema> (optional) - Database/schema name; defaults to the current database

=back

=head1 METHODS

=over 4

=item C<introspect()>

Returns a Perl data structure in schema format.

=item C<generate_yaml()>

Returns the schema as a YAML string.

=back

=cut
