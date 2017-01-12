use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;

use App::GAWM;

my $result = test_app( 'App::GAWM' => [qw(help position)] );
like( $result->stdout, qr{position}, 'descriptions' );

$result = test_app( 'App::GAWM' => [qw(position)] );
like( $result->error, qr{\-\-file}, 'need --file' );

$result = test_app( 'App::GAWM' => [qw(position --file t/not_exists)] );
like( $result->error, qr{doesn't exist}, 'not exists' );

$result = test_app( 'App::GAWM' => [qw(gen --dir t/S288c)] );
$result = test_app( 'App::GAWM' => [qw(position --file t/spo11_hot.pos.txt)] );
like( $result->stdout, qr{size set to},    'got chr.sizes from directory' );
like( $result->stdout, qr{Processing \[2\]}, 'got fasta files from directory' );
like( $result->stdout, qr{Exists 2},       'inserted' );

done_testing();
