use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help position)] );
like( $result->stdout, qr{position}, 'descriptions' );

$result = test_app( 'App::GAWM' => [qw(position)] );
like( $result->error, qr{\-\-file}, 'need --file' );

$result = test_app( 'App::GAWM' => [qw(position t/not_exists)] );
like( $result->error, qr{need no inputs}, 'need no inputs' );

$result = test_app( 'App::GAWM' => [qw(position --file t/not_exists)] );
like( $result->error, qr{doesn't exist}, 'not exists' );

test_app( 'App::GAWM' => [qw(init drop)] );
test_app( 'App::GAWM' => [qw(gen --dir t/S288c)] );
$result
    = test_app( 'App::GAWM' => [qw(position --file t/spo11_hot.pos.txt --tag spo11 --type hot)] );
like( $result->stdout, qr{Insert positions to gawm}, 'start message' );
like( $result->stdout, qr{Exists 71},                'inserted' );
like( $result->stdout, qr{Exists 2894},              'ofgsw' );

done_testing();
