use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help stat)] );
like( $result->stdout, qr{stat}, 'descriptions' );

$result = test_app( 'App::GAWM' => [qw(stat t/not_exists)] );
like( $result->error, qr{need no inputs}, 'need no inputs' );

test_app( 'App::GAWM' => [qw(init drop)] );
test_app( 'App::GAWM' => [qw(gen --dir t/S288c)] );
test_app( 'App::GAWM' => [qw(position --file t/spo11_hot.pos.txt --tag spo11 --type hot)] );
{
    my $temp = Path::Tiny->tempfile;
    $result = test_app( 'App::GAWM' => [ qw(stat --by type -o ), $temp->stringify ] );
    like( $result->stdout, qr{Do stats on }, 'start message' );
}

test_app( 'App::GAWM' => [qw(gcwave)] );
{
    my $temp = Path::Tiny->tempfile;
    $result = test_app( 'App::GAWM' => [ qw(stat --by tag -o ), $temp->stringify ] );
    like( $result->stdout, qr{Do stats on }, 'start message' );
}

test_app( 'App::GAWM' => [qw(count insert --file t/spo11_hot.pos.txt)] );
test_app( 'App::GAWM' => [qw(count count)] );
test_app( 'App::GAWM' => [qw(swcv)] );

{
    my $temp = Path::Tiny->tempfile;
    $result = test_app( 'App::GAWM' =>
            [ qw(stat --index --chart --by tt --replace POS=HotSpots -o ), $temp->stringify ] );
    like( $result->stdout, qr{Do stats on }, 'start message' );
    like( $result->stdout, qr{INDEX},        'index sheet' );
}

done_testing();
