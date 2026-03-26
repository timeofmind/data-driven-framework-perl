package DataDriven::Framework::Generator::Migration;

use strict;
use warnings;
use Moo;
use Carp qw(croak);
use POSIX qw(strftime);
use DataDriven::Framework::Model::ValueType;
use DataDriven::Framework::Generator::SQL;

has from_model => (is => 'ro', required => 1);
has to_model   => (is => 'ro', required => 1);
has ops        => (is => 'lazy');

sub _build_ops {
    my ($self) = @_;
    require DataDriven::Framework::Diff::SchemaComparator;
    my $cmp = DataDriven::Framework::Diff::SchemaComparator->new(
        from_model => $self->from_model,
        to_model   => $self->to_model,
    );
    return [$cmp->diff];
}

# Returns SQL migration string
sub generate_sql {
    my ($self) = @_;
    my $ops = $self->ops;
    return '' unless @$ops;

    my $from_ver = $self->from_model->schema_version;
    my $to_ver   = $self->to_model->schema_version;
    my $ts       = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $hash     = $self->to_model->model_hash;

    my @sql;
    push @sql, <<SQL;
-- ============================================================
-- Migration: $from_ver -> $to_ver
-- Generated: $ts
-- ============================================================
-- Review this file carefully before applying.
-- WARNING comments indicate potentially destructive changes.
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

SQL

    for my $op (@$ops) {
        push @sql, $self->_op_to_sql($op);
    }

    push @sql, <<SQL;
SET FOREIGN_KEY_CHECKS = 1;

-- Record migration
INSERT INTO `_framework_schema_version`
  (schema_version, framework_version, applied_at, model_hash, notes)
VALUES
  ('$to_ver', '0.01', NOW(), '$hash', 'migration from $from_ver');

INSERT INTO `_framework_migrations`
  (from_version, to_version, applied_at, migration_sql, checksum)
VALUES
  ('$from_ver', '$to_ver', NOW(), 'see file', '$hash');
SQL

    return join("\n", @sql);
}

# Returns a human-readable Markdown summary
sub generate_summary {
    my ($self) = @_;
    my $ops = $self->ops;
    my $from_ver = $self->from_model->schema_version;
    my $to_ver   = $self->to_model->schema_version;

    my @lines;
    push @lines, "# Migration Summary: $from_ver → $to_ver\n";

    unless (@$ops) {
        push @lines, "_No changes detected._";
        return join("\n", @lines);
    }

    my (@creates, @drops, @adds, @removes, @modifies);
    for my $op (@$ops) {
        if    ($op->{op} eq 'create_table')       { push @creates,  $op }
        elsif ($op->{op} eq 'drop_table')         { push @drops,    $op }
        elsif ($op->{op} eq 'add_column')         { push @adds,     $op }
        elsif ($op->{op} =~ /^drop_column/)       { push @removes,  $op }
        elsif ($op->{op} =~ /^modify/)            { push @modifies, $op }
    }

    if (@creates) {
        push @lines, "## New Tables\n";
        push @lines, "- `" . $_->{table} . "` (class: " . $_->{class} . ")" for @creates;
    }
    if (@drops) {
        push @lines, "\n## ⚠ Dropped Tables (DESTRUCTIVE)\n";
        push @lines, "- `" . $_->{table} . "` — " . ($_->{warning} // '') for @drops;
    }
    if (@adds) {
        push @lines, "\n## Added Columns\n";
        push @lines, "- `" . $_->{table} . "`.`" . $_->{column} . "`" for @adds;
    }
    if (@removes) {
        push @lines, "\n## ⚠ Dropped Columns (DESTRUCTIVE)\n";
        push @lines, "- `" . $_->{table} . "`.`" . $_->{column} . "` — " . ($_->{warning} // '') for @removes;
    }
    if (@modifies) {
        push @lines, "\n## Modified Columns\n";
        push @lines, "- `" . $_->{table} . "`.`" . $_->{column} . "`" . ($_->{warning} ? " ⚠ " . $_->{warning} : '') for @modifies;
    }

    return join("\n", @lines);
}

sub _op_to_sql {
    my ($self, $op) = @_;
    my $table = $op->{table};
    my $col   = $op->{column};

    if ($op->{op} eq 'create_table') {
        my $class = $self->to_model->class($op->{class});
        my $gen = DataDriven::Framework::Generator::SQL->new(model => $self->to_model);
        return $gen->_class_to_sql($class, $self->to_model) . "\n";
    }

    if ($op->{op} eq 'drop_table') {
        return "-- WARNING: " . ($op->{warning} // '') . "\n"
             . "DROP TABLE IF EXISTS `$table`;\n";
    }

    if ($op->{op} eq 'add_column') {
        my $slot = $op->{slot};
        my $gen  = DataDriven::Framework::Generator::SQL->new(model => $self->to_model);
        my $col_def = $gen->_slot_to_column($slot, $self->to_model, $table);
        $col_def =~ s/^\s+//;
        # Remove PRIMARY KEY from col_def if it got in there (shouldn't for add)
        $col_def =~ s/,\s*PRIMARY KEY.*//s;
        return "ALTER TABLE `$table` ADD COLUMN $col_def;\n";
    }

    if ($op->{op} eq 'drop_column') {
        return "-- WARNING: " . ($op->{warning} // '') . "\n"
             . "ALTER TABLE `$table` DROP COLUMN `$col`;\n";
    }

    if ($op->{op} eq 'modify_column' || $op->{op} eq 'modify_column_default') {
        my $slot = $op->{slot};
        my $gen  = DataDriven::Framework::Generator::SQL->new(model => $self->to_model);
        my $col_def = $gen->_slot_to_column($slot, $self->to_model, $table);
        $col_def =~ s/^\s+//;
        $col_def =~ s/,\s*PRIMARY KEY.*//s;
        my $warn = $op->{warning} ? "-- WARNING: $op->{warning}\n" : '';
        return "${warn}ALTER TABLE `$table` MODIFY COLUMN $col_def;\n";
    }

    if ($op->{op} eq 'add_unique') {
        my $name = $op->{name};
        my $cols = join(', ', map { "`$_`" } @{$op->{columns}});
        return "ALTER TABLE `$table` ADD UNIQUE KEY `$name` ($cols);\n";
    }

    if ($op->{op} eq 'drop_unique') {
        my $name = $op->{name};
        return "ALTER TABLE `$table` DROP INDEX `$name`;\n";
    }

    return "-- Unknown operation: $op->{op}\n";
}

1;

__END__

=head1 NAME

DataDriven::Framework::Generator::Migration - Generate SQL migration from schema diff

=head1 SYNOPSIS

    use DataDriven::Framework::Generator::Migration;

    my $migrator = DataDriven::Framework::Generator::Migration->new(
        from_model => $old_model,
        to_model   => $new_model,
    );

    my $sql     = $migrator->generate_sql;
    my $summary = $migrator->generate_summary;

=head1 DESCRIPTION

Compares two models using L<DataDriven::Framework::Diff::SchemaComparator> and
generates MySQL migration SQL and a human-readable Markdown summary.

Destructive operations (DROP TABLE, DROP COLUMN) are annotated with C<-- WARNING:>
comments in the SQL.

The generated SQL also records the migration in the C<_framework_schema_version>
and C<_framework_migrations> tables.

=head1 METHODS

=over 4

=item C<generate_sql()>

Returns the migration SQL as a string.

=item C<generate_summary()>

Returns a Markdown summary of all changes.

=back

=cut
