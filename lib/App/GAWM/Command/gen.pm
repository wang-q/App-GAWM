package App::GAWM::Command::gen;
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
        [ 'dir=s',    'file/dire of genome', ],
        [ 'size|s=s', 'chr.sizes', ],
        [ 'name|n=s', 'common name', ],
        [],
        [ 'length=i',   'break genome into pieces',            { default => 500_000 } ],
        [ 'fill=i',     'fill gaps smaller than this value',   { default => 50 } ],
        [ 'min=i',      'skip pieces smaller than this value', { default => 5000 } ],
        [ 'parallel=i', 'run in parallel mode',                { default => 1 } ],
        { show_defaults => 1, }
    );
}

sub usage_desc {
    return "gawm gen --dir <file or dir> [options]";
}

sub description {
    my $desc;
    $desc .= ucfirst(abstract) . ".\n";
    return $desc;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( @{$args} != 0 ) {
        my $message = "This command need no inputs. Pass genome files by --dir. \n\tIt found";
        $message .= sprintf " [%s]", $_ for @{$args};
        $message .= ".\n";
        $self->usage_error($message);
    }

    if ( !$opt->{dir} ) {
        $self->usage_error("--dir is needed\n");
    }
    elsif ( Path::Tiny::path( $opt->{dir} )->is_file ) {

        # to array ref
        $opt->{dir} = [ $opt->{dir} ];
    }
    elsif ( Path::Tiny::path( $opt->{dir} )->is_dir ) {
        my @paths = Path::Tiny::path( $opt->{dir} )->children(qr/\.(fa|fas|fasta)$/);
        if ( !@paths ) {
            $self->usage_error("Can't find .fa[ast] files in [$opt->{dir}]\n");
        }

        # replace dir with files
        $opt->{dir} = [ map { $_->stringify } @paths ];
    }
    else {
        $self->usage_error("[$opt->{dir}] doesn't exist\n");
    }

    if ( !$opt->{name} ) {
        $opt->{name} = Path::Tiny::path( $opt->{dir}[0] )->basename;
        $opt->{name} = s/\.fa[sta].*?$//;
    }

    if ( !$opt->{size} ) {
        if ( Path::Tiny::path( $opt->{dir}[0] )->parent->child('chr.sizes')->is_file ) {
            $opt->{size}
                = Path::Tiny::path( $opt->{dir}[0] )->parent->child('chr.sizes')
                ->absolute->stringify;
            print "--size set to $opt->{size}\n";
        }
        else {
            $self->usage_error("--size chr.sizes is needed\n");
        }
    }
    elsif ( !-e $opt->{size} ) {
        $self->usage_error("--size $opt->{size} doesn't exist\n");
    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $stopwatch = AlignDB::Stopwatch->new;

    {    # clear chr and align
        $stopwatch->block_message("Init database $opt->{db}");
        my $client = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        );
        $client->ns("$opt->{db}.chr")->drop;
        $client->ns("$opt->{db}.align")->drop;
    }

    {    # populate chr
        my $client = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        );

        #@type MongoDB::Collection
        my $coll_chr = $client->ns("$opt->{db}.chr");

        my @chrs;
        my $length_of = App::RL::Common::read_sizes( $opt->{size} );
        for my $key ( keys %{$length_of} ) {
            push @chrs,
                {
                name        => $key,
                length      => $length_of->{$key},
                common_name => $opt->{name},
                };
        }
        $coll_chr->insert_many( \@chrs );

        $stopwatch->block_message(
            "There are [@{[$coll_chr->count]}] documents in collection chromosome\n");
    }

    #----------------------------#
    # worker
    #----------------------------#
    my $worker = sub {
        my ( $self, $chunk_ref, $chunk_id ) = @_;
        my $infile = $chunk_ref->[0];
        my $wid    = MCE->wid;

        my $inner    = AlignDB::Stopwatch->new;
        my $basename = Path::Tiny::path($infile)->basename;
        $inner->block_message("Process task [$chunk_id] by worker #$wid. [$basename]");

        #@type MongoDB::Database
        my $db = MongoDB::MongoClient->new(
            host          => $opt->{host},
            port          => $opt->{port},
            query_timeout => -1,
        )->get_database( $opt->{db} );

        my $seq_of = App::Fasops::Common::read_fasta($infile);

        for my $chr_name ( keys %{$seq_of} ) {
            print "    Processing chromosome $chr_name\n";

            my $chr_seq    = $seq_of->{$chr_name};
            my $chr_length = length $chr_seq;

            # find chromosome OID
            #@type MongoDB::Collection
            my $coll_chr = $db->get_collection('chr');
            my $chr_id
                = $coll_chr->find_one( { 'common_name' => $opt->{name}, 'name' => $chr_name } );
            return unless $chr_id;
            $chr_id = $chr_id->{_id};

            my $ambiguous_set = AlignDB::IntSpan->new;
            for ( my $pos = 0; $pos < $chr_length; $pos++ ) {
                my $base = substr $chr_seq, $pos, 1;
                if ( $base =~ /[^ACGT-]/i ) {
                    $ambiguous_set->add( $pos + 1 );
                }
            }
            printf "Ambiguous region for %s:\n    %s\n", $chr_name, $ambiguous_set->runlist;

            my $valid_set = AlignDB::IntSpan->new("1-$chr_length");
            $valid_set->subtract($ambiguous_set);
            $valid_set = $valid_set->fill( $opt->{fill} - 1 );
            printf "Valid region for %s:\n    %s\n", $chr_name, $valid_set->runlist;

            my @regions;    # ([start, end], [start, end], ...)
            for my $set ( $valid_set->sets ) {
                my $size = $set->size;
                next if $size < $opt->{min};

                my @set_regions;
                my $pos = $set->min;
                my $max = $set->max;
                while ( $max - $pos + 1 > $opt->{length} ) {
                    push @set_regions, [ $pos, $pos + $opt->{length} - 1 ];
                    $pos += $opt->{length};
                }
                if ( scalar @set_regions > 0 ) {
                    $set_regions[-1]->[1] = $max;
                }
                else {
                    @set_regions = ( [ $pos, $max ] );
                }
                push @regions, @set_regions;
            }

            # insert to collection align
            #@type MongoDB::Collection
            my $coll_align = $db->get_collection('align');
            for my $region (@regions) {
                my ( $start, $end ) = @{$region};
                my $length  = $end - $start + 1;
                my $runlist = AlignDB::IntSpan->new("$start-$end")->runlist;
                my $seq     = substr $chr_seq, $start - 1, $length;

                my $data = {
                    chr => {
                        common_name => $opt->{name},
                        _id         => $chr_id,
                        name        => $chr_name,
                        start       => $start,
                        end         => $end,
                        strand      => '+',
                        runlist     => $runlist,
                    },
                    length => $length,
                    seq    => $seq,
                };
                $coll_align->insert_one($data);
            }
        }

        $inner->block_message( "$infile has been processed.", "duration" );

        return;
    };

    #----------------------------#
    # start
    #----------------------------#
    printf "Processing [@{[ scalar(@{$opt->{dir}}) ]}] fasta files\n";
    my $mce = MCE->new( max_workers => $opt->{parallel}, );
    $mce->foreach( $opt->{dir}, $worker, );    # foreach implies chunk_size => 1.

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

        {
            my $name = "chr";
            $stopwatch->block_message("Indexing $name");
            my $coll    = $db->get_collection($name);
            my $indexes = $coll->indexes;
            $indexes->create_one( [ common_name => 1, name => 1 ], { unique => 1 } );
        }

        {
            my $name = "align";
            $stopwatch->block_message("Indexing $name");
            my $coll    = $db->get_collection($name);
            my $indexes = $coll->indexes;
            $indexes->create_one( [ "chr.name" => 1, "chr.start" => 1, "chr.end" => 1 ] );
        }

        $stopwatch->block_message( App::GAWM::Common::check_coll( $db, 'chr',   '_id' ) );
        $stopwatch->block_message( App::GAWM::Common::check_coll( $db, 'align', 'chr._id' ) );
    }

    $stopwatch->end_message( "All files have been processed.", "duration" );
}

1;
