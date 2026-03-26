use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin/lib";

use DataDriven::Framework::Schema::Parser;
use DataDriven::Framework::Schema::Resolver;
use DataDriven::Framework::Schema::Validator;
use DataDriven::Framework::Generator::Docs;
use TestUtils qw(simple_schema_yaml);

sub build_model {
    my $parser   = DataDriven::Framework::Schema::Parser->new;
    my $resolver = DataDriven::Framework::Schema::Resolver->new;
    my $validator= DataDriven::Framework::Schema::Validator->new;
    my $model    = $parser->parse(simple_schema_yaml());
    $resolver->resolve($model);
    $validator->validate_or_die($model);
    return $model;
}

my $model  = build_model();
my $outdir = tempdir(CLEANUP => 1);

my $gen = DataDriven::Framework::Generator::Docs->new(
    model      => $model,
    output_dir => $outdir,
);

my @files = $gen->generate;
ok(scalar @files > 0, 'docs generated at least one file');

# Check index.md
my $index = File::Spec->catfile($outdir, 'index.md');
ok(-f $index, 'index.md created');

open my $fh, '<', $index or die "Cannot open $index: $!";
my $content = do { local $/; <$fh> };
close $fh;

like($content, qr/Schema Documentation/, 'index has heading');
like($content, qr/<!-- BEGIN GENERATED -->/, 'index has begin marker');
like($content, qr/<!-- END GENERATED -->/, 'index has end marker');
like($content, qr/User/, 'index mentions User');
like($content, qr/Post/, 'index mentions Post');
like($content, qr/Status/, 'index mentions Status enum');

# Check user.md
my $user_md = File::Spec->catfile($outdir, 'user.md');
ok(-f $user_md, 'user.md created');

open $fh, '<', $user_md or die "Cannot open $user_md: $!";
my $user_content = do { local $/; <$fh> };
close $fh;

like($user_content, qr/# User/, 'user.md has heading');
like($user_content, qr/## Fields/, 'user.md has Fields section');
like($user_content, qr/username/, 'user.md mentions username');
like($user_content, qr/required/i, 'user.md mentions required');
like($user_content, qr/## Constraints/, 'user.md has Constraints section');
like($user_content, qr/Unique/, 'user.md mentions unique constraint');

# Regeneration: custom content outside markers is preserved
open $fh, '>>', $user_md or die $!;
print $fh "\n\n## Custom Section\n\nMy custom content here.\n";
close $fh;

# Regenerate
$gen->generate;

open $fh, '<', $user_md or die $!;
my $regen_content = do { local $/; <$fh> };
close $fh;

like($regen_content, qr/My custom content here/, 'custom content preserved after regeneration');
like($regen_content, qr/## Fields/, 'generated content still present after regeneration');

# Check post.md
my $post_md = File::Spec->catfile($outdir, 'post.md');
ok(-f $post_md, 'post.md created');

open $fh, '<', $post_md or die $!;
my $post_content = do { local $/; <$fh> };
close $fh;

like($post_content, qr/belongs_to/, 'post.md mentions relationship');
like($post_content, qr/User/, 'post.md mentions User relationship target');

done_testing;
