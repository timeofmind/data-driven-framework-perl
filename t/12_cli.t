use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use FindBin qw($Bin);

my $cli     = File::Spec->catfile($Bin, '..', 'bin', 'ddframework');
my $schema  = File::Spec->catfile($Bin, '..', 'examples', 'device_management', 'schema', 'device.yaml');
my $lib_dir = File::Spec->catfile($Bin, '..', 'lib');

# Skip if Perl binary is not available
my $perl = $^X;

sub run_cli {
    my (@args) = @_;
    my $cmd = "$perl -I$lib_dir $cli " . join(' ', map { "'$_'" } @args) . " 2>&1";
    my $out = `$cmd`;
    my $rc  = $? >> 8;
    return ($out, $rc);
}

# Version
my ($out, $rc) = run_cli('version');
is($rc, 0, 'version exits 0');
like($out, qr/0\.01/, 'version shows version number');

# Help
($out, $rc) = run_cli('help');
is($rc, 0, 'help exits 0');
like($out, qr/validate/, 'help mentions validate');
like($out, qr/generate-sql/, 'help mentions generate-sql');

SKIP: {
    skip 'Device schema not found', 20 unless -f $schema;

    # Validate
    ($out, $rc) = run_cli('validate', '--schema', $schema);
    is($rc, 0, 'validate exits 0');
    like($out, qr/valid/, 'validate output says valid');

    # Generate SQL
    my $tmpdir = tempdir(CLEANUP => 1);
    my $sql_out = File::Spec->catfile($tmpdir, 'schema.sql');
    ($out, $rc) = run_cli('generate-sql', '--schema', $schema, '--output', $sql_out);
    is($rc, 0, 'generate-sql exits 0');
    ok(-f $sql_out, 'SQL file created');
    open my $fh, '<', $sql_out or die $!;
    my $sql = do { local $/; <$fh> };
    close $fh;
    like($sql, qr/CREATE TABLE/, 'generated SQL has CREATE TABLE');
    like($sql, qr/devices/, 'generated SQL has devices table');

    # Generate OpenAPI
    my $oa_out = File::Spec->catfile($tmpdir, 'openapi.yaml');
    ($out, $rc) = run_cli('generate-openapi', '--schema', $schema, '--output', $oa_out);
    is($rc, 0, 'generate-openapi exits 0');
    ok(-f $oa_out, 'OpenAPI file created');

    # Generate JSON Schema
    my $js_out = File::Spec->catfile($tmpdir, 'schema.json');
    ($out, $rc) = run_cli('generate-json-schema', '--schema', $schema, '--output', $js_out);
    is($rc, 0, 'generate-json-schema exits 0');
    ok(-f $js_out, 'JSON Schema file created');

    # Generate UI
    my $ui_dir = File::Spec->catfile($tmpdir, 'ui');
    ($out, $rc) = run_cli('generate-ui', '--schema', $schema, '--output', $ui_dir);
    is($rc, 0, 'generate-ui exits 0');
    ok(-d $ui_dir, 'UI output dir created');

    # Generate Docs
    my $docs_dir = File::Spec->catfile($tmpdir, 'docs');
    ($out, $rc) = run_cli('generate-docs', '--schema', $schema, '--output', $docs_dir);
    is($rc, 0, 'generate-docs exits 0');
    ok(-d $docs_dir, 'Docs output dir created');
    ok(-f File::Spec->catfile($docs_dir, 'index.md'), 'docs index.md created');
}

# Unknown command
($out, $rc) = run_cli('nonexistent-command');
isnt($rc, 0, 'unknown command exits non-zero');

# Missing args
($out, $rc) = run_cli('validate');
isnt($rc, 0, 'validate without --schema exits non-zero');

done_testing;
