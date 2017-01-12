package App::GAWM::Command::position;
use strict;
use warnings;
use autodie;

use App::GAWM -command;
use App::GAWM::Common;

use MongoDB;
$MongoDB::BSON::looks_like_number = 1;
use MongoDB::OID;

use MCE;

use constant abstract => 'generate database from fasta files';

sub opt_spec {
    return (
        [ 'host=s', 'MongoDB server IP/Domain name', { default => "localhost" } ],
        [ 'port=i', 'MongoDB server IP/Domain name', { default => "27017" } ],
        [ 'db|d=s', 'MongoDB database name',         { default => "gawm" } ],
        [],
        [ 'file=s@', 'position files', ],
        [ 'tag=s@',  'position tags', ],
        [ 'type=s@', 'position types', ],
        [],
        [ 'style=s',    'intact or center',                      { default => "intact" } ],
        [ 'parallel=i', 'run in parallel mode',                  { default => 1 } ],
        [ 'batch=i',    'aligns processed in one child process', { default => 10 } ],
        { show_defaults => 1, }
    );
}

sub usage_desc {
    return "gawm position --file <position file> --tag <tag> --type <type> [options]";
}

sub description {
    my $desc;
    $desc .= ucfirst(abstract) . ".\n";
    return $desc;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( @{$args} != 0 ) {
        my $message = "This command need no inputs. Pass position files by --file. \n\tIt found";
        $message .= sprintf " [%s]", $_ for @{$args};
        $message .= ".\n";
        $self->usage_error($message);
    }

    if ( !$opt->{file} ) {
        $self->usage_error("--file is needed");
    }
    elsif ( !Path::Tiny::path( $opt->{dir} )->is_file ) {
        $self->usage_error("The input file [$opt->{file}] doesn't exist.");
    }

    if ( !$opt->{tag} ) {
        $self->usage_error("--tag is needed");
    }

    if ( !$opt->{type} ) {
        $self->usage_error("--type is needed");
    }

    if ( @{ $opt->{file} } != @{ $opt->{tag} } or @{ $opt->{file} } != @{ $opt->{type} } ) {

    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $stopwatch = AlignDB::Stopwatch->new;
    $stopwatch->start_message("Insert positions to $opt->{db}");

    #----------------------------------------------------------#
    # workers
    #----------------------------------------------------------#
    my $worker_insert = sub {
        my ( $self, $chunk_ref, $chunk_id ) = @_;
        my $job = $chunk_ref->[0];

        my $wid = MCE->wid;

        my $inner_watch = AlignDB::Stopwatch->new;
        $inner_watch->block_message("Process task [$chunk_id] by worker #$wid");

        my ( $file, $tag, $type ) = @$job;
        print "Reading file [$file]\n";

        # wait forever for responses
        #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        )->get_database( $opt->{db} );

        #@type MongoDB::Collection
        my $coll_align = $db->get_collection('align');

        my @data;
        open my $data_fh, '<', $file;
        while ( my $string = <$data_fh> ) {
            next unless defined $string;
            chomp $string;

            my $info = App::RL::Common::decode_header($string);
            next unless defined $info->{chr};
            $info->{tag}  = $tag;
            $info->{type} = $type;

            my $align = $coll_align->find_one(
                {   'chr.name'  => $info->{chr},
                    'chr.start' => { '$lte' => $info->{start} },
                    'chr.end'   => { '$gte' => $info->{end} }
                }
            );
            if ( !$align ) {
                print "    Can't locate an align for $string\n";
                next;
            }
            else {
                my $length          = $info->{end} - $info->{start} + 1;
                my $ofg_align_start = $info->{start} - $align->{chr}{start} + 1;
                my $ofg_align_end   = $info->{end} - $align->{chr}{start} + 1;
                my $ofg_seq         = substr $align->{seq}, $ofg_align_start - 1, $length;
                my $ofg_gc          = App::Fasops::Common::calc_gc_ratio( [$ofg_seq] );
                push @data,
                    {
                    align => {
                        _id   => $align->{_id},
                        start => $ofg_align_start,
                        end   => $ofg_align_end,
                        runlist =>
                            AlignDB::IntSpan->new->add_pair( $ofg_align_start, $ofg_align_end )
                            ->runlist,
                    },
                    chr => {
                        name  => $info->{chr},
                        start => $info->{start},
                        end   => $info->{end},
                        runlist =>
                            AlignDB::IntSpan->new->add_pair( $info->{start}, $info->{end} )
                            ->runlist,
                    },
                    length => $length,
                    gc     => $ofg_gc,
                    tag    => $tag,
                    type   => $type,
                    };
            }
        }
        close $data_fh;

        print "Inserting file [$file]\n";

        #@type MongoDB::Collection
        my $coll_ofg = $db->get_collection('ofg');
        while ( scalar @data ) {
            my @batching = splice @data, 0, 10000;
            $coll_ofg->insert_many( \@batching );
        }
        print "Insert done.\n";
    };

    my $worker_sw = sub {
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
        my $coll_ofg = $db->get_collection('ofg');

        #@type MongoDB::Collection
        my $coll_ofgsw = $db->get_collection('ofgsw');

        for my $job (@jobs) {
            my $align = App::GAWM::Common::process_message( $db, $job->{_id} );
            next unless $align;

            my @align_ofgs = $coll_ofg->find( { 'align._id' => $align->{_id} } )->all;
            if ( @align_ofgs == 0 ) {
                warn "No ofgs in this align\n";
                next;
            }
            printf "    Find %d ofgs in this align\n", scalar @align_ofgs;

            my $align_set = AlignDB::IntSpan->new->add_pair( 1, $align->{length} );

            #----------------------------#
            # ofgsw
            #----------------------------#
            my $window_maker = AlignDB::Window->new(
                sw_size          => 100,
                max_out_distance => 20,
                max_in_distance  => 20,
            );

            for my $ofg (@align_ofgs) {
                my @rsws;
                if ( $opt->{style} eq 'intact' ) {
                    @rsws = $window_maker->center_intact_window(
                        $align_set,
                        $ofg->{align}{start},
                        $ofg->{align}{end}
                    );
                }
                elsif ( $opt->{style} eq 'center' ) {
                    @rsws = $window_maker->center_window(
                        $align_set,
                        $ofg->{align}{start},
                        $ofg->{align}{end}
                    );
                }

                my @ofgsws;
                for my $rsw (@rsws) {
                    my $ofgsw = {
                        chr => {
                            name  => $align->{chr}{name},
                            start => $rsw->{set}->min + $align->{chr}{start} - 1,
                            end   => $rsw->{set}->max + $align->{chr}{start} - 1,
                        },
                        align => {
                            _id   => $align->{_id},
                            start => $rsw->{set}->min,
                            end   => $rsw->{set}->max,
                        },
                        ofg => {
                            _id      => $ofg->{_id},
                            tag      => $ofg->{tag},
                            type     => $ofg->{type},
                            distance => $rsw->{distance},
                        },
                        type   => $rsw->{type},
                        length => $rsw->{set}->size,
                    };
                    $ofgsw->{chr}{runlist}
                        = AlignDB::IntSpan->new->add_pair( $ofgsw->{chr}{start},
                        $ofgsw->{chr}{end} )->runlist;
                    $ofgsw->{align}{runlist}
                        = AlignDB::IntSpan->new->add_pair( $ofgsw->{align}{start},
                        $ofgsw->{align}{end} )->runlist;

                    # pre allocate
                    $ofgsw->{bed_count} = 0;
                    my $ofgsw_seq = substr $align->{seq}, $rsw->{set}->min - 1, $ofgsw->{length};
                    $ofgsw->{gc} = {
                        gc => App::Fasops::Common::calc_gc_ratio( [$ofgsw_seq] ),
                        mean => 0.0,
                        cv   => 0.0,
                        std  => 0.0,
                    };

                    push @ofgsws, $ofgsw;
                }
                $coll_ofgsw->insert_many( \@ofgsws );
            }
        }
    };

    {    # ofg
        my $client = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        );

        #@type MongoDB::Collection
        my $coll = $client->ns("$opt->{db}.ofg");
        $coll->drop;

        my @jobs;
        for my $i ( 0 .. @{ $opt->{file} } - 1 ) {
            push @jobs, [ $opt->{file}[$i], $opt->{tag}[$i], $opt->{type}[$i], ];
        }

        my $mce = MCE->new( max_workers => $opt->{parallel}, );
        $mce->foreach( \@jobs, $worker_insert, );    # foreach implies chunk_size => 1.

        $stopwatch->block_message("Indexing ofg");

        #@type MongoDB::IndexView
        my $indexes = $coll->indexes;
        $indexes->create_one( [ 'align._id' => 1 ] );
        $indexes->create_one( [ 'chr.name'  => 1, 'chr.start' => 1, 'chr.end' => 1 ] );
        $indexes->create_one( [ tag         => 1 ] );
        $indexes->create_one( [ type        => 1 ] );

        $stopwatch->block_message( check_coll( $opt->{db}, "ofg", '_id' ) );
    }

    {    # ofgsw
            #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        )->get_database( $opt->{db} );

        # get aligns
        my @jobs = $db->get_collection('align')->find->fields( { _id => 1 } )->all;

        #@type MongoDB::Collection
        my $coll = $db->get_collection('ofgsw');
        $coll->drop;

        my $mce = MCE->new( max_workers => $opt->{parallel}, chunk_size => $opt->{batch}, );
        $mce->forchunk( \@jobs, $worker_sw, );

        # indexing
        $stopwatch->block_message("Indexing ofgsw");

        #@type MongoDB::IndexView
        my $indexes = $coll->indexes;
        $indexes->create_one( [ 'align._id'    => 1 ] );
        $indexes->create_one( [ 'ofg._id'      => 1 ] );
        $indexes->create_one( [ 'chr.name'     => 1, 'chr.start' => 1, 'chr.end' => 1 ] );
        $indexes->create_one( [ type           => 1 ] );
        $indexes->create_one( [ 'ofg.distance' => 1 ] );
        $indexes->create_one( { 'ofg.tag'  => 1 } );
        $indexes->create_one( { 'ofg.type' => 1 } );

        $stopwatch->block_message( check_coll( $db, 'ofgsw', '_id' ) );
    }

    $stopwatch->end_message( "All files have been processed.", "duration" );
}

1;
