package App::GAWM::Command::count;
use strict;
use warnings;
use autodie;

use MongoDB;
use MCE;

use App::GAWM -command;
use App::GAWM::Common;

sub abstract {
    return 'add position files and count intersections';
}

sub opt_spec {
    return (
        [ 'host=s', 'MongoDB server IP/Domain name', { default => "localhost" } ],
        [ 'port=i', 'MongoDB server port',           { default => "27017" } ],
        [ 'db|d=s', 'MongoDB database name',         { default => "gawm" } ],
        [],
        [ 'file|f=s@', 'position files', ],
        [],
        [ 'parallel=i', 'run in parallel mode',                  { default => 1 } ],
        [ 'batch=i',    'aligns processed in one child process', { default => 10 } ],
        { show_defaults => 1, }
    );
}

sub usage_desc {
    return "gawm count <action> --file <position file> [options]";
}

sub description {
    my $desc;
    $desc .= ucfirst(abstract) . ".\n";
    $desc .= <<'MARKDOWN';

List of actions:

* insert: add position files
* count:  count intersections

MARKDOWN

    return $desc;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( @{$args} != 1 ) {
        my $message = "This command need one action.\n\tIt found";
        $message .= sprintf " [%s]", $_ for @{$args};
        $message .= ".\n";
        $self->usage_error($message);
    }

    if ( $args->[0] eq "insert" ) {
        if ( !$opt->{file} ) {
            $self->usage_error("--file is needed");
        }
        else {
            for my $f ( @{ $opt->{file} } ) {
                if ( !Path::Tiny::path($f)->is_file ) {
                    $self->usage_error("The input file [$opt->{file}] doesn't exist.");
                }
            }
        }
    }
    elsif ( $args->[0] eq "count" ) {    # just OK
    }
    else {
        $self->usage_error("Action [$args->[0]] is invalid.");
    }

}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $stopwatch = AlignDB::Stopwatch->new;
    $stopwatch->start_message("Count positions of $opt->{db}");

    $stopwatch->block_message( "Total position files are " . scalar( @{ $opt->{file} } ) )
        if $opt->{file};

    #----------------------------------------------------------#
    # workers
    #----------------------------------------------------------#
    my $worker_insert = sub {
        my ( $self, $chunk_ref, $chunk_id ) = @_;
        my $file = $chunk_ref->[0];

        my $wid = MCE->wid;

        my $inner_watch = AlignDB::Stopwatch->new;
        $inner_watch->block_message("Process task [$chunk_id] by worker #$wid");

        print "Reading file [$file]\n";

        # wait forever for responses
        #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
            bson_codec    => BSON->new( prefer_numeric => 1, ),
        )->get_database( $opt->{db} );

        #@type MongoDB::Collection
        my $coll_align = $db->get_collection('align');

        my @positions;
        open my $data_fh, '<', $file;
        while ( my $string = <$data_fh> ) {
            next unless defined $string;
            chomp $string;

            my $info = App::RL::Common::decode_header($string);
            next unless defined $info->{chr};

            my $align = $coll_align->find_one(
                {   'chr.name'  => $info->{chr},
                    'chr.start' => { '$lte' => $info->{start} },
                    'chr.end'   => { '$gte' => $info->{end} },
                }
            );

            if ( !$align ) {
                print "    Can't locate an align for $string\n";
                next;
            }
            push @positions,
                {
                align => { _id => $align->{_id}, },
                chr   => {
                    name  => $info->{chr},
                    start => $info->{start},
                    end   => $info->{end},
                    runlist =>
                        AlignDB::IntSpan->new->add_pair( $info->{start}, $info->{end} )->runlist,
                },
                };
        }
        close $data_fh;

        print "Inserting file [$file]\n";

        # https://www.mongodb.com/blog/post/introducing-the-1-0-perl-driver
        # BSON encoding and decoding
        #@type MongoDB::Collection
        my $coll_position = $db->get_collection('position');
        while ( scalar @positions ) {
            my @batching = splice @positions, 0, 10000;
            $coll_position->insert_many( \@batching );
        }
        print "Insert done.\n";
    };

    my $worker_count = sub {
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
            bson_codec    => BSON->new( prefer_numeric => 1, ),
        )->get_database( $opt->{db} );

        #@type MongoDB::Collection
        my $coll_align = $db->get_collection('align');

        #@type MongoDB::Collection
        my $coll_gsw = $db->get_collection('gsw');

        #@type MongoDB::Collection
        my $coll_ofgsw = $db->get_collection('ofgsw');

        #@type MongoDB::Collection
        my $coll_position = $db->get_collection('position');

        for my $job (@jobs) {
            my $align = $coll_align->find_one( { _id => $job->{_id} } );
            if ( !defined $align ) {
                printf "Can't find align for %s\n", $job->{_id};
                next;
            }

            printf "Process align %s:%s-%s\n", $align->{chr}{name}, $align->{chr}{start},
                $align->{chr}{end};

            # all positions in this align
            my @positions = $coll_position->find( { 'align._id' => $align->{_id} } )->all;
            next unless @positions;
            printf "    %d positions in this align\n", scalar @positions;
            my $pos_chr_set = AlignDB::IntSpan->new;
            for (@positions) {
                $pos_chr_set->add_runlist( $_->{chr}{runlist} );
            }

            # all gsws in this align
            my @gsws = $coll_gsw->find( { 'align._id' => $align->{_id} } )->all;
            my %gsw_count_of;
            for my $gsw (@gsws) {
                next if $pos_chr_set->intersect( $gsw->{chr}{runlist} )->is_empty;

                my $count = count_pos_in_sw( $coll_position, $align->{_id}, $gsw );

                if ($count) {
                    $gsw_count_of{ $gsw->{_id} } = $count;
                }
                else {
                    printf "gsw %s matching wrong\n", $gsw->{chr}{runlist};
                }
            }
            printf "    %d gsws in this align, %d overlapping with positions\n", scalar @gsws,
                scalar keys %gsw_count_of;

            # all ofgsw in this align
            my @ofgsws = $coll_ofgsw->find( { 'align._id' => $align->{_id} } )->all;
            my %ofgsw_count_of;
            for my $ofgsw (@ofgsws) {
                next if $pos_chr_set->intersect( $ofgsw->{chr}{runlist} )->is_empty;

                my $count = count_pos_in_sw( $coll_position, $align->{_id}, $ofgsw );

                if ($count) {
                    $ofgsw_count_of{ $ofgsw->{_id} } = $count;
                }
                else {
                    printf "ofgsw %s matching wrong\n", $ofgsw->{chr}{runlist};
                }
            }
            printf "    %d ofgsws in this align, %d overlapping with positions\n", scalar @ofgsws,
                scalar keys %ofgsw_count_of;

            for my $key ( keys %gsw_count_of ) {
                $coll_gsw->update_one(
                    { _id    => $key },
                    { '$set' => { pos_count => $gsw_count_of{$key}, } },
                );
            }
            for my $key ( keys %ofgsw_count_of ) {
                $coll_ofgsw->update_one(
                    { _id    => $key },
                    { '$set' => { pos_count => $ofgsw_count_of{$key}, } },
                );
            }
        }
    };

    if ( $args->[0] eq "insert" ) {

        #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
            bson_codec    => BSON->new( prefer_numeric => 1, ),
        )->get_database( $opt->{db} );

        #@type MongoDB::Collection
        my $coll = $db->get_collection('position');
        $coll->drop;

        my $mce = MCE->new( max_workers => $opt->{parallel}, );
        $mce->foreach( $opt->{file}, $worker_insert, );    # foreach implies chunk_size => 1.

        #@type MongoDB::IndexView
        my $indexes = $coll->indexes;
        $indexes->create_one( [ 'align._id' => 1 ] );
        $indexes->create_one( [ chr_name => 1, chr_start => 1, chr_end => 1 ] );

        $stopwatch->block_message( App::GAWM::Common::check_coll( $db, 'position', '_id' ) );
    }

    if ( $args->[0] eq "count" ) {

        #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
            bson_codec    => BSON->new( prefer_numeric => 1, ),
        )->get_database( $opt->{db} );

        my @aligns = $db->get_collection('align')->find->fields( { _id => 1 } )->all;
        $stopwatch->block_message( "Total align: " . scalar(@aligns) );

        my $mce = MCE->new( max_workers => $opt->{parallel}, chunk_size => $opt->{batch}, );
        $mce->forchunk( \@aligns, $worker_count, );

        $stopwatch->block_message( App::GAWM::Common::check_coll( $db, 'gsw',   'pos_count' ) );
        $stopwatch->block_message( App::GAWM::Common::check_coll( $db, 'ofgsw', 'pos_count' ) );
    }

    $stopwatch->end_message( "", "duration" );
}

sub count_pos_in_sw {

    #@type MongoDB::Collection
    my $coll     = shift;
    my $align_id = shift;
    my $sw       = shift;

    my $count = $coll->count(
        {   'align._id' => $align_id,
            '$or'       => [

                # pos    |----|
                # sw  |----|
                {   'chr.start' => {
                        '$gte' => $sw->{chr}{start},
                        '$lte' => $sw->{chr}{end},
                    }
                },

                # pos |----|
                # sw    |----|
                {   'chr.end' => {
                        '$gte' => $sw->{chr}{start},
                        '$lte' => $sw->{chr}{end},
                    }
                },

                # pos |--------|
                # sw    |----|
                {   'chr.start' => { '$lte' => $sw->{chr}{start}, },
                    'chr.end'   => { '$gte' => $sw->{chr}{end}, }
                },

                # pos   |----|
                # sw  |--------|
                {   'chr.start' => { '$gte' => $sw->{chr}{start}, },
                    'chr.end'   => { '$lte' => $sw->{chr}{end}, }
                },
            ]
        }
    );

    return $count;
}

1;
