package App::GAWM::Command::swcv;
use strict;
use warnings;
use autodie;

use App::GAWM -command;
use App::GAWM::Common;

use MongoDB;
$MongoDB::BSON::looks_like_number = 1;
use MongoDB::OID;

use MCE;

use AlignDB::GC;

use constant abstract => 'update CV for ofgsw and gsw';

sub opt_spec {
    return (
        [ 'host=s', 'MongoDB server IP/Domain name', { default => "localhost" } ],
        [ 'port=i', 'MongoDB server IP/Domain name', { default => "27017" } ],
        [ 'db|d=s', 'MongoDB database name',         { default => "gawm" } ],
        [],
        [ 'stat_segment_size=i', '', { default => 500 } ],
        [ 'stat_window_size=i',  '', { default => 100 } ],
        [ 'stat_window_step=i',  '', { default => 100 } ],
        [],
        [ 'parallel=i', 'run in parallel mode',                  { default => 1 } ],
        [ 'batch=i',    'aligns processed in one child process', { default => 10 } ],
        { show_defaults => 1, }
    );
}

sub usage_desc {
    return "gawm swcv [options]";
}

sub description {
    my $desc;
    $desc .= ucfirst(abstract) . ".\n";
    return $desc;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( @{$args} != 0 ) {
        my $message = "This command need no inputs.\n\tIt found";
        $message .= sprintf " [%s]", $_ for @{$args};
        $message .= ".\n";
        $self->usage_error($message);
    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $stopwatch = AlignDB::Stopwatch->new;
    $stopwatch->start_message("Update CV of sliding windows of $opt->{db}");

    # retrieve all _id from align
    my @aligns;
    {
        my $client = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        );

        @aligns = $client->ns("$opt->{db}.align")->find->fields( { _id => 1 } )->all;
        $stopwatch->block_message("There are [@{[scalar(@aligns)]}] aligns totally.");
    }

    #----------------------------#
    # worker
    #----------------------------#
    my $worker = sub {
        my ( $self, $chunk_ref, $chunk_id ) = @_;
        my @jobs = @{$chunk_ref};

        my $wid = MCE->wid;

        my $inner_watch = AlignDB::Stopwatch->new;
        $inner_watch->block_message("Process task [$chunk_id] by worker #$wid");

        # wait forever for responses
        #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        )->get_database( $opt->{db} );

        #@type MongoDB::Collection
        my $coll_ofgsw = $db->get_collection('ofgsw');

        #@type MongoDB::Collection
        my $coll_gsw = $db->get_collection('gsw');

        # AlignDB::GC
        my $obj = AlignDB::GC->new(
            stat_window_size => $opt->{stat_window_size},
            stat_window_step => $opt->{stat_window_step},
            skip_mdcw        => 1,
        );

        #@type MongoDB::Collection
        my $coll_align = $db->get_collection('align');
        for my $job (@jobs) {
            my $align = $coll_align->find_one( { _id => $job->{_id} } );
            printf "Process align %s:%s-%s\n", $align->{chr}{name}, $align->{chr}{start},
                $align->{chr}{end};

            my $align_set = AlignDB::IntSpan->new( "1-" . $align->{length} );

            #----------------------------#
            # ofgsw
            #----------------------------#
            my @ofgsws = $coll_ofgsw->find( { "align._id" => $align->{_id} } )->all;
            printf "    Updating %d ofgsws\n", scalar @ofgsws;
            my %stat_ofgsw_of;

            #----------------------------#
            # gsw
            #----------------------------#
            my @gsws = $coll_gsw->find( { "align._id" => $align->{_id} } )->all;
            printf "    Updating %d gsws\n", scalar @gsws;
            my %stat_gsw_of;

            #----------------------------#
            # calc
            #----------------------------#
            for my $ofgsw (@ofgsws) {
                my $window_set = AlignDB::IntSpan->new( $ofgsw->{align}{runlist} );
                my $resize_set
                    = center_resize( $window_set, $align_set, $opt->{stat_segment_size} );

                if ( !$resize_set ) {
                    print "    Can't resize window!\n";
                    next;
                }

                my ( $gc_mean, $gc_std, $gc_cv, $gc_mdcw )
                    = $obj->segment_gc_stat( [ $align->{seq} ], $resize_set );

                $stat_ofgsw_of{ $ofgsw->{_id} } = {
                    "gc.mean" => $gc_mean,
                    "gc.cv"   => $gc_cv,
                    "gc.std"  => $gc_std,
                };
            }

            for my $gsw (@gsws) {
                my $window_set = AlignDB::IntSpan->new( $gsw->{align}{runlist} );
                my $resize_set
                    = center_resize( $window_set, $align_set, $opt->{stat_segment_size} );

                if ( !$resize_set ) {
                    print "    Can't resize window!\n";
                    next;
                }

                my ( $gc_mean, $gc_std, $gc_cv, $gc_mdcw )
                    = $obj->segment_gc_stat( [ $align->{seq} ], $resize_set );

                $stat_gsw_of{ $gsw->{_id} } = {
                    "gc.mean" => $gc_mean,
                    "gc.cv"   => $gc_cv,
                    "gc.std"  => $gc_std,
                };
            }

            #----------------------------#
            # update
            #----------------------------#
            # MongoDB::OID would be overloaded to string when as hash key
            for my $key ( keys %stat_ofgsw_of ) {
                $coll_ofgsw->update_one(
                    { _id    => MongoDB::OID->new( value => $key ) },
                    { '$set' => $stat_ofgsw_of{$key}, },
                );
            }
            for my $key ( keys %stat_gsw_of ) {
                $coll_gsw->update_one(
                    { _id    => MongoDB::OID->new( value => $key ) },
                    { '$set' => $stat_gsw_of{$key}, },
                );
            }
        }
    };

    #----------------------------#
    # start
    #----------------------------#
    my $mce = MCE->new( max_workers => $opt->{parallel}, chunk_size => $opt->{batch}, );
    $mce->forchunk( \@aligns, $worker, );

    #----------------------------#
    # index and check
    #----------------------------#
    {
        #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        )->get_database( $opt->{db} );

        $stopwatch->block_message( App::GAWM::Common::check_coll( $db, 'ofgsw', 'gc.cv' ) );
        $stopwatch->block_message( App::GAWM::Common::check_coll( $db, 'gsw',   'gc.cv' ) );
    }

    $stopwatch->end_message( "", "duration" );
}

#----------------------------------------------------------#
# Subroutines
#----------------------------------------------------------#

sub center_resize {
    my AlignDB::IntSpan $old_set    = shift;
    my AlignDB::IntSpan $parent_set = shift;
    my $resize                      = shift;

    # find the middles of old_set
    my $half_size           = int( $old_set->size / 2 );
    my $midleft             = $old_set->at($half_size);
    my $midright            = $old_set->at( $half_size + 1 );
    my $midleft_parent_idx  = $parent_set->index($midleft);
    my $midright_parent_idx = $parent_set->index($midright);

    return unless $midleft_parent_idx and $midright_parent_idx;

    # map to parent
    my $parent_size  = $parent_set->size;
    my $half_resize  = int( $resize / 2 );
    my $new_left_idx = $midleft_parent_idx - $half_resize + 1;
    $new_left_idx = 1 if $new_left_idx < 1;
    my $new_right_idx = $midright_parent_idx + $half_resize - 1;
    $new_right_idx = $parent_size if $new_right_idx > $parent_size;

    my $new_set = $parent_set->slice( $new_left_idx, $new_right_idx );

    return $new_set;
}

1;
