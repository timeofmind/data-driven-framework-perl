package DataDriven::Framework::Diff::SchemaComparator;

use strict;
use warnings;
use Moo;
use Carp qw(croak);

has from_model => (is => 'ro', required => 1);
has to_model   => (is => 'ro', required => 1);

# Returns a list of diff operations (hashrefs) describing what changed.
sub diff {
    my ($self) = @_;
    my @ops;

    my $from = $self->from_model;
    my $to   = $self->to_model;

    my %from_classes = map { $_->name => $_ } $from->classes;
    my %to_classes   = map { $_->name => $_ } $to->classes;

    # Dropped classes
    for my $name (sort keys %from_classes) {
        unless (exists $to_classes{$name}) {
            next if $from_classes{$name}->abstract;
            push @ops, {
                op      => 'drop_table',
                class   => $name,
                table   => $from_classes{$name}->effective_table,
                warning => 'DESTRUCTIVE: drops all data in this table',
            };
        }
    }

    # Added classes
    for my $name (sort keys %to_classes) {
        unless (exists $from_classes{$name}) {
            next if $to_classes{$name}->abstract;
            push @ops, {
                op    => 'create_table',
                class => $name,
                table => $to_classes{$name}->effective_table,
            };
        }
    }

    # Modified classes
    for my $name (sort keys %to_classes) {
        next unless exists $from_classes{$name};
        my $from_class = $from_classes{$name};
        my $to_class   = $to_classes{$name};
        next if $to_class->abstract;

        push @ops, $self->_diff_class($from_class, $to_class, $to);
    }

    return @ops;
}

sub _diff_class {
    my ($self, $from_class, $to_class, $to_model) = @_;
    my @ops;
    my $table = $to_class->effective_table;

    my %from_slots = map { $_->name => $_ } @{$from_class->all_slots};
    my %to_slots   = map { $_->name => $_ } @{$to_class->all_slots};

    # Dropped columns
    for my $col_name (sort keys %from_slots) {
        unless (exists $to_slots{$col_name}) {
            push @ops, {
                op      => 'drop_column',
                table   => $table,
                column  => $col_name,
                warning => 'DESTRUCTIVE: drops column and all its data',
            };
        }
    }

    # Added columns
    for my $col_name (sort keys %to_slots) {
        unless (exists $from_slots{$col_name}) {
            push @ops, {
                op     => 'add_column',
                table  => $table,
                column => $col_name,
                slot   => $to_slots{$col_name},
            };
        }
    }

    # Changed columns
    for my $col_name (sort keys %to_slots) {
        next unless exists $from_slots{$col_name};
        my $from_slot = $from_slots{$col_name};
        my $to_slot   = $to_slots{$col_name};

        if ($from_slot->type ne $to_slot->type) {
            push @ops, {
                op        => 'modify_column',
                table     => $table,
                column    => $col_name,
                from_type => $from_slot->type,
                to_type   => $to_slot->type,
                slot      => $to_slot,
                warning   => 'Type change may cause data loss',
            };
        } elsif (($from_slot->required ? 1 : 0) != ($to_slot->required ? 1 : 0)) {
            push @ops, {
                op       => 'modify_column',
                table    => $table,
                column   => $col_name,
                change   => 'nullability',
                from_nullable => !$from_slot->required,
                to_nullable   => !$to_slot->required,
                slot     => $to_slot,
            };
        } elsif (!_defaults_equal($from_slot->default, $to_slot->default)) {
            push @ops, {
                op       => 'modify_column_default',
                table    => $table,
                column   => $col_name,
                from_default => $from_slot->default,
                to_default   => $to_slot->default,
                slot     => $to_slot,
            };
        }
    }

    # Constraints
    push @ops, $self->_diff_constraints($from_class, $to_class);

    return @ops;
}

sub _diff_constraints {
    my ($self, $from_class, $to_class) = @_;
    my @ops;
    my $table = $to_class->effective_table;

    my %from_uq = map { join(',', sort @{$_->columns}) => $_ } $from_class->unique_constraints;
    my %to_uq   = map { join(',', sort @{$_->columns}) => $_ } $to_class->unique_constraints;

    for my $key (sort keys %from_uq) {
        unless (exists $to_uq{$key}) {
            push @ops, {
                op      => 'drop_unique',
                table   => $table,
                columns => $from_uq{$key}->columns,
                name    => $from_uq{$key}->effective_name($table),
            };
        }
    }
    for my $key (sort keys %to_uq) {
        unless (exists $from_uq{$key}) {
            push @ops, {
                op      => 'add_unique',
                table   => $table,
                columns => $to_uq{$key}->columns,
                name    => $to_uq{$key}->effective_name($table),
            };
        }
    }

    return @ops;
}

sub _defaults_equal {
    my ($a, $b) = @_;
    return 1 if !defined($a) && !defined($b);
    return 0 if  defined($a) != defined($b);
    return $a eq $b;
}

1;

__END__

=head1 NAME

DataDriven::Framework::Diff::SchemaComparator - Compare two Models and produce a diff

=head1 SYNOPSIS

    use DataDriven::Framework::Diff::SchemaComparator;

    my $cmp = DataDriven::Framework::Diff::SchemaComparator->new(
        from_model => $old_model,
        to_model   => $new_model,
    );
    my @ops = $cmp->diff;

=head1 DESCRIPTION

Compares two L<DataDriven::Framework::Model> objects and returns a list of
operations needed to migrate from the C<from_model> to the C<to_model>.

Each operation is a hashref with an C<op> key:

=over 4

=item C<create_table> - a new class/table was added

=item C<drop_table> - a class/table was removed (marked DESTRUCTIVE)

=item C<add_column> - a new slot was added to a class

=item C<drop_column> - a slot was removed (marked DESTRUCTIVE)

=item C<modify_column> - a slot's type or nullability changed

=item C<modify_column_default> - a slot's default value changed

=item C<add_unique> / C<drop_unique> - unique constraint added/removed

=back

Pass the result to L<DataDriven::Framework::Generator::Migration> to produce SQL.

=cut
