use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(commands )] );

like(
    $result->stdout,
    qr{list the application's commands},
    'default commands outputs'
);

is( $result->stderr, '', 'nothing sent to sderr' );

is( $result->error, undef, 'threw no exceptions' );

done_testing(3);
