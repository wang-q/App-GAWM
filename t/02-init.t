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

$result = test_app( 'App::GAWM' => [qw(init invalid)] );
like( $result->error, qr{invalid}, 'invalid action' );

$result = test_app( 'App::GAWM' => [qw(init dump --dir t/not_exists)] );
like( $result->error, qr{doesn't exist}, 'not exists' );

$result = test_app( 'App::GAWM' => [qw(init check)] );
like( $result->stdout, qr{\*OK\*: find},       'check mongo in $PATH' );
like( $result->stdout, qr{\*OK\*: successful}, 'connect mongodb' );

$result = test_app( 'App::GAWM' => [qw(init drop)] );
like( $result->stdout, qr{\*OK\*: system}, 'drop (initiate)' );

$result = test_app( 'App::GAWM' => [qw(init restore --dir t/Atha)] );
like( $result->stdout, qr{\*OK\*: system}, 'restore' );

{
    my $tempdir = Path::Tiny->tempdir;
    $result = test_app( 'App::GAWM' => [ qw(init dump --dir ), $tempdir->stringify ] );
    like( $result->stdout, qr{\*OK\*: system}, 'system dump' );
    ok( $tempdir->child("gawm")->is_dir,                     "dump dir" );
    ok( $tempdir->child("gawm")->child("chr.bson")->is_file, "dump file" );
}

done_testing();
