requires 'App::Cmd', '0.330';
requires 'MongoDB', '1.2.1';
requires 'MCE', '1.810';
requires 'Path::Tiny', '0.076';
requires 'YAML::Syck', '1.29';

requires 'AlignDB::IntSpan', '1.1.0';
requires 'AlignDB::Stopwatch';
requires 'AlignDB::Window';
requires 'App::RL::Common';
requires 'App::Fasops::Common';

requires 'perl', '5.010001';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
