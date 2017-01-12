package App::GAWM::Common;
use strict;
use warnings;
use autodie;

use 5.010001;

use Carp qw();
use IPC::Cmd;
use Path::Tiny;
use YAML::Syck qw();

use AlignDB::Stopwatch;
use AlignDB::Window;
use App::RL::Common;
use App::Fasops::Common;

sub check_coll {

    #@type MongoDB::Database
    my $db    = shift;
    my $name  = shift;
    my $field = shift;

    #@type MongoDB::Collection
    my $coll = $db->get_collection($name);

    my $total      = $coll->find->count;
    my $exists     = $coll->find( { $field => { '$exists' => 1 } } )->count;
    my $non_exists = $coll->find( { $field => { '$exists' => 0 } } )->count;

    return "For collection [$name], check field [$field]:\n"
        . "    Total $total\n    Exists $exists\n    Non exists $non_exists\n";
}

sub process_message {
    #@type MongoDB::Database
    my $db       = shift;
    my $align_id = shift;

    #@type MongoDB::Collection
    my $coll_align = $db->get_collection('align');
    my $align = $coll_align->find_one( { _id => $align_id } );
    if ( !defined $align ) {
        printf "Can't find align for %s\n", $align_id;
        return;
    }

    printf "Process align %s(%s):%s-%s\n", $align->{chr}{name}, $align->{chr}{strand},
        $align->{chr}{start},
        $align->{chr}{end};

    return $align;
}

1;
