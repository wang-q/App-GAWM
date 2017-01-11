use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help init)] );
like( $result->stdout, qr{init}, 'descriptions' );

$result = test_app( 'App::GAWM' => [qw(init)] );
like( $result->error, qr{need .+? action}, 'need action' );

$result = test_app( 'App::GAWM' => [qw(init dump)] );
like( $result->error, qr{\-\-dir}, 'need --dir' );

$result = test_app( 'App::GAWM' => [qw(init dump --dir t/not_exists)] );
like( $result->error, qr{doesn't exist}, 'not exists' );

done_testing();
