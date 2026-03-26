requires 'perl', '5.020';

requires 'Moo',                     '2.000';
requires 'MooX::Types::MooseLike',  '0.29';
requires 'Type::Tiny',              '1.012';
requires 'YAML',                '0.67';
requires 'JSON::PP',                '2.27';
requires 'DBI',                     '1.643';
requires 'Carp',                    '1.29';
requires 'Scalar::Util',            '1.50';
requires 'List::Util',              '1.50';
requires 'File::Path',              '2.12';
requires 'File::Spec',              '3.40';
requires 'File::Basename',          '0';
requires 'Getopt::Long',            '2.51';
requires 'Term::ANSIColor',         '4.06';
requires 'Digest::MD5',             '2.55';
requires 'POSIX',                   '0';

on 'runtime' => sub {
    requires 'DBD::mysql', '4.050';
};

on 'test' => sub {
    requires 'Test::More',       '1.302';
    requires 'Test::Exception',  '0.43';
    requires 'Test::Deep',       '1.130';
    requires 'File::Temp',       '0.2309';
};

on 'develop' => sub {
    requires 'Dist::Zilla', '6.000';
    requires 'Pod::Coverage::TrustPod', '0';
    requires 'Test::Pod',    '1.51';
    requires 'Test::Pod::Coverage', '1.08';
};
