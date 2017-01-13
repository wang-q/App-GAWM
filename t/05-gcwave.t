use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help gcwave)] );
like( $result->stdout, qr{gcwave}, 'descriptions' );

test_app( 'App::GAWM' => [qw(init drop)] );
test_app( 'App::GAWM' => [qw(gen --dir t/S288c)] );
$result = test_app( 'App::GAWM' => [qw(gcwave)] );
like( $result->stdout, qr{Insert gcwaves to gawm}, 'start message' );
like( $result->stdout, qr{Exists 215},             'inserted' );
like( $result->stdout, qr{Exists 3114},            'gsw' );

done_testing();
