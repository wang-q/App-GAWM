use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help swcv)] );
like( $result->stdout, qr{swcv}, 'descriptions' );

$result = test_app( 'App::GAWM' => [qw(gen --dir t/S288c)] );
$result = test_app( 'App::GAWM' => [qw(swcv)] );
like( $result->stdout, qr{Update CV},   'start message' );
like( $result->stdout, qr{Exists 0},    'not inserted' );
like( $result->stdout, qr{Exists 3114}, 'gsw' );

done_testing();
