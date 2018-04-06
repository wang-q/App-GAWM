use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help count)] );
like( $result->stdout, qr{count}, 'descriptions' );

$result = test_app( 'App::GAWM' => [qw(count)] );
like( $result->error, qr{need .+? action}, 'need action' );

$result = test_app( 'App::GAWM' => [qw(count insert)] );
like( $result->error, qr{\-\-file}, 'need --file' );

$result = test_app( 'App::GAWM' => [qw(count invalid)] );
like( $result->error, qr{invalid}, 'invalid action' );

$result = test_app( 'App::GAWM' => [qw(count insert --file t/not_exists)] );
like( $result->error, qr{doesn't exist}, 'not exists' );

SKIP: {
    skip "MongoDB not installed", 4
        unless IPC::Cmd::can_run('mongo')
        or IPC::Cmd::can_run('mongodump')
        or IPC::Cmd::can_run('mongorestore');

    test_app( 'App::GAWM' => [qw(init drop)] );
    test_app( 'App::GAWM' => [qw(gen --dir t/S288c)] );
    test_app( 'App::GAWM' => [qw(gcwave)] );
    $result = test_app( 'App::GAWM' => [qw(count insert --file t/spo11_hot.pos.txt)] );
    like( $result->stdout, qr{Count positions of}, 'start message' );
    like( $result->stdout, qr{Exists 71},          'inserted' );
    $result = test_app( 'App::GAWM' => [qw(count count)] );
    like( $result->stdout, qr{Count positions of}, 'start message' );
    like( $result->stdout, qr{Exists 3114},        'count' );
}

done_testing();
