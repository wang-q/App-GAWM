requires 'App::Cmd',   '0.330';
requires 'JSON',       '2.97001';
requires 'MongoDB',    '2.0.1';
requires 'MCE',        '1.810';
requires 'Path::Tiny', '0.076';
requires 'YAML::Syck', '1.29';

requires 'AlignDB::IntSpan', '1.1.0';
requires 'AlignDB::GC';
requires 'AlignDB::Stopwatch';
requires 'AlignDB::Window';
requires 'AlignDB::ToXLSX';
requires 'App::RL::Common';
requires 'App::Fasops::Common';

requires 'perl', '5.010001';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
