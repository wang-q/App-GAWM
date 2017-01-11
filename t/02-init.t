use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help init)] );
like( $result->stdout, qr{init}, 'descriptions' );

done_testing();
