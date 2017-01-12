use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help gen)] );
like( $result->stdout, qr{gen}, 'descriptions' );

$result = test_app( 'App::GAWM' => [qw(gen)] );
like( $result->error, qr{\-\-dir}, 'need --dir' );

$result = test_app( 'App::GAWM' => [qw(gen t/not_exists)] );
like( $result->error, qr{\-\-dir}, 'need --dir' );

$result = test_app( 'App::GAWM' => [qw(gen --dir t/not_exists)] );
like( $result->error, qr{doesn't exist}, 'not exists' );


done_testing();
