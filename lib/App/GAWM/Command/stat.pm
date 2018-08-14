package App::GAWM::Command::stat;
use strict;
use warnings;
use autodie;

use MongoDB;
use AlignDB::ToXLSX;

use App::GAWM -command;
use App::GAWM::Common;

sub abstract {
    return 'do stats on gawm databases';
}

sub opt_spec {
    return (
        [ 'host=s', 'MongoDB server IP/Domain name', { default => "localhost" } ],
        [ 'port=i', 'MongoDB server port',           { default => "27017" } ],
        [ 'db|d=s', 'MongoDB database name',         { default => "gawm" } ],
        [],
        [ 'outfile|o=s', 'output filename', ],
        [ 'by=s',       'tag, type or tt', { default => "tag" } ],
        [ 'replace=s@', 'replace strings in axis names', ],
        [ 'index',      'add an index sheet', ],
        [ 'chart',      'add charts', ],
        { show_defaults => 1, }
    );
}

sub usage_desc {
    return "gawm stat [options]";
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

    if ( $opt->{by} eq "tag" or $opt->{by} eq "type" or $opt->{by} eq "tt" ) {    # OK
    }
    else {
        $self->usage_error("[$opt->{by}] is invalid\n");
    }

    if ( $opt->{replace} ) {
        my %replace;
        for my $s ( @{ $opt->{replace} } ) {
            if ( $s !~ /\=/ ) {
                $self->usage_error("The replacing string [$opt->{replace}] is invalid.");
            }
            my ( $key, $value ) = split "=", $s;
            $replace{$key} = $value;
        }
        $opt->{replace} = \%replace;
    }
    else {
        $opt->{replace} = {};
    }

    if ( !$opt->{outfile} ) {
        $opt->{outfile} = "$opt->{db}.mg.xlsx";
    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $stopwatch = AlignDB::Stopwatch->new;
    $stopwatch->start_message("Do stats on $opt->{db}");

    my $toxlsx = AlignDB::ToXLSX->new(
        outfile => $opt->{outfile},
        replace => $opt->{replace},
    );

    #@type MongoDB::Database
    my $db = MongoDB::MongoClient->new(
        host          => $opt->{host},
        port          => $opt->{port},
        query_timeout => -1,
    )->get_database( $opt->{db} );

    #----------------------------------------------------------#
    # chart -- gc_cv
    #----------------------------------------------------------#
    my $chart_gc_cv = sub {
        my $sheet   = shift;
        my $data    = shift;
        my $x_title = shift;

        my %option = (
            x_column    => 0,
            y_column    => 1,
            first_row   => 1,
            last_row    => 16,
            x_max_scale => 15,
            y_data      => $data->[1],
            x_title     => $x_title,
            y_title     => "Window GC",
            top         => 1,
            left        => 6,
        );
        $toxlsx->draw_y( $sheet, \%option );

        $option{y_column} = 2;
        $option{y_title}  = "Window CV";
        $option{y_data}   = $data->[2];
        $option{top} += 18;
        $toxlsx->draw_y( $sheet, \%option );

        $option{y_column} = 3;
        $option{y_title}  = "POS count";
        $option{y_data}   = $data->[3];
        $option{top} += 18;
        $toxlsx->draw_y( $sheet, \%option );

        $option{y_column}  = 1;
        $option{y_title}   = "Window GC";
        $option{y_data}    = $data->[1];
        $option{y2_column} = 2;
        $option{y2_data}   = $data->[2];
        $option{y2_title}  = "Window CV";
        $option{top}       = 1;
        $option{left}      = 12;
        $toxlsx->draw_2y( $sheet, \%option );
    };

    #----------------------------------------------------------#
    # worksheet -- distance_to_trough
    #----------------------------------------------------------#
    my $distance_to_trough = sub {
        my $sheet_name = 'distance_to_trough';
        my $sheet;
        $toxlsx->row(0);
        $toxlsx->column(0);

        #@type MongoDB::Collection
        my $coll = $db->get_collection('gsw');
        my $exists = $coll->count( { "gc.cv" => { '$exists' => 1 } } );
        if ( !$exists ) {
            print "    gsw.gc.cv doesn't exist\n";
            print "    Skip sheet $sheet_name\n";
            return;
        }

        my @names = qw{_id AVG_gc AVG_cv AVG_pos COUNT};
        {    # header
            $sheet = $toxlsx->write_header( $sheet_name, { header => \@names } );
        }

        my $data = [];
        push @{$data}, [] for @names;
        {    # content
            my @docs = $coll->aggregate(
                [   { '$match' => { 'gce.distance' => { '$lte' => 15 } } },
                    {   '$group' => {
                            $names[0] => '$gce.distance',
                            $names[1] => { '$avg' => '$gc.gc' },
                            $names[2] => { '$avg' => '$gc.cv' },
                            $names[3] => { '$avg' => '$pos_count' },
                            $names[4] => { '$sum' => 1 },
                        }
                    },
                    { '$sort' => { $names[0] => 1 } },
                ]
            )->all;
            for my $row (@docs) {
                for my $i ( 0 .. $#names ) {
                    push @{ $data->[$i] }, $row->{ $names[$i] };
                }
            }
            $sheet->write( $toxlsx->row, $toxlsx->column, $data, $toxlsx->format->{NORMAL} );
        }

        if ( $opt->{chart} ) {    # chart
            $chart_gc_cv->( $sheet, $data, "Distance to GC troughs" );
        }

        print "Sheet [$sheet_name] has been generated.\n";
    };

    #----------------------------------------------------------#
    # worksheet -- distance_to_crest
    #----------------------------------------------------------#
    my $distance_to_crest = sub {
        my $sheet_name = 'distance_to_crest';
        my $sheet;
        $toxlsx->row(0);
        $toxlsx->column(0);

        #@type MongoDB::Collection
        my $coll = $db->get_collection('gsw');
        my $exists = $coll->count( { 'gc.cv' => { '$exists' => 1 } } );
        if ( !$exists ) {
            print "    gsw.gc.cv doesn't exist\n";
            print "    Skip sheet $sheet_name\n";
            return;
        }

        my @names = qw{_id AVG_gc AVG_cv AVG_pos COUNT};
        {    # header
            $sheet = $toxlsx->write_header( $sheet_name, { header => \@names } );
        }

        my $data = [];
        push @{$data}, [] for @names;
        {    # content
            my @docs = $coll->aggregate(
                [   { '$match' => { 'gce.distance_crest' => { '$lte' => 15 } } },
                    {   '$group' => {
                            $names[0] => '$gce.distance_crest',
                            $names[1] => { '$avg' => '$gc.gc' },
                            $names[2] => { '$avg' => '$gc.cv' },
                            $names[3] => { '$avg' => '$pos_count' },
                            $names[4] => { '$sum' => 1 },
                        }
                    },
                    { '$sort' => { $names[0] => 1 } },
                ]
            )->all;
            for my $row (@docs) {
                for my $i ( 0 .. $#names ) {
                    push @{ $data->[$i] }, $row->{ $names[$i] };
                }
            }
            $sheet->write( $toxlsx->row, $toxlsx->column, $data, $toxlsx->format->{NORMAL} );
        }

        if ( $opt->{chart} ) {    # chart
            $chart_gc_cv->( $sheet, $data, "Distance to GC crests" );
        }

        print "Sheet [$sheet_name] has been generated.\n";
    };

    #----------------------------------------------------------#
    # worksheet -- gradient
    #----------------------------------------------------------#
    my $gradient = sub {
        my $sheet_name = 'gradient';
        my $sheet;
        $toxlsx->row(0);
        $toxlsx->column(0);

        #@type MongoDB::Collection
        my $coll = $db->get_collection('gsw');
        my $exists = $coll->count( { 'gc.cv' => { '$exists' => 1 } } );
        if ( !$exists ) {
            print "    gsw.gc.cv doesn't exist\n";
            print "    Skip sheet $sheet_name\n";
            return;
        }

        my @names = qw{_id AVG_gc AVG_cv AVG_pos COUNT};
        {    # header
            $sheet = $toxlsx->write_header( $sheet_name, { header => \@names } );
        }

        my $data = [];
        push @{$data}, [] for @names;
        {    # content
            my @docs = $coll->aggregate(
                [   { '$match' => { 'gce.gradient' => { '$gte' => 1, '$lte' => 40 } } },
                    {   '$group' => {
                            $names[0] => '$gce.gradient',
                            $names[1] => { '$avg' => '$gc.gc' },
                            $names[2] => { '$avg' => '$gc.cv' },
                            $names[3] => { '$avg' => '$pos_count' },
                            $names[4] => { '$sum' => 1 },
                        }
                    },
                    { '$sort' => { $names[0] => 1 } },
                ]
            )->all;
            for my $row (@docs) {
                for my $i ( 0 .. $#names ) {
                    push @{ $data->[$i] }, $row->{ $names[$i] };
                }
            }
            $sheet->write( $toxlsx->row, 0, $data, $toxlsx->format->{NORMAL} );
        }

        if ( $opt->{chart} ) {    # chart
            my %option = (
                x_column    => 0,
                y_column    => 1,
                first_row   => 1,
                last_row    => 41,
                x_max_scale => 40,
                y_data      => $data->[1],
                x_title     => "Gradient",
                y_title     => "Window GC",
                top         => 1,
                left        => 6,
            );
            $toxlsx->draw_y( $sheet, \%option );

            $option{y_column} = 2;
            $option{y_title}  = "Window CV";
            $option{y_data}   = $data->[2];
            $option{top} += 18;
            $toxlsx->draw_y( $sheet, \%option );

            $option{y_column} = 3;
            $option{y_title}  = "POS count";
            $option{y_data}   = $data->[3];
            $option{top} += 18;
            $toxlsx->draw_y( $sheet, \%option );

            $option{y_column}  = 1;
            $option{y_title}   = "Window GC";
            $option{y_data}    = $data->[1];
            $option{y2_column} = 2;
            $option{y2_data}   = $data->[2];
            $option{y2_title}  = "Window CV";
            $option{top}       = 1;
            $option{left}      = 12;
            $toxlsx->draw_2y( $sheet, \%option );
        }

        print "Sheet [$sheet_name] has been generated.\n";
    };

    #----------------------------------------------------------#
    # worksheet -- ofg_all
    #----------------------------------------------------------#
    my $ofg_all = sub {
        my $sheet_name = 'ofg_all';
        my $sheet;
        $toxlsx->row(0);
        $toxlsx->column(0);

        #@type MongoDB::Collection
        my $coll = $db->get_collection('ofgsw');
        my $exists = $coll->count( { 'gc.cv' => { '$exists' => 1 } } );
        if ( !$exists ) {
            print "    ofgsw.gc.cv doesn't exist\n";
            print "    Skip sheet $sheet_name\n";
            return;
        }

        my @names = qw{_id AVG_gc AVG_cv AVG_pos COUNT};
        {    # header
            $sheet = $toxlsx->write_header( $sheet_name, { header => \@names } );
        }

        my $data = [];
        push @{$data}, [] for @names;
        {    # content
            my @docs = $coll->aggregate(
                [   { '$match' => { 'ofg.distance' => { '$lte' => 15 } } },
                    {   '$group' => {
                            $names[0] => '$ofg.distance',
                            $names[1] => { '$avg' => '$gc.gc' },
                            $names[2] => { '$avg' => '$gc.cv' },
                            $names[3] => { '$avg' => '$pos_count' },
                            $names[4] => { '$sum' => 1 },
                        }
                    },
                    { '$sort' => { $names[0] => 1 } },
                ]
            )->all;
            for my $row (@docs) {
                for my $i ( 0 .. $#names ) {
                    push @{ $data->[$i] }, $row->{ $names[$i] };
                }
            }
            $sheet->write( $toxlsx->row, 0, $data, $toxlsx->format->{NORMAL} );
        }

        if ( $opt->{chart} ) {    # chart
            $chart_gc_cv->( $sheet, $data, "Distance to ofg" );
        }

        print "Sheet [$sheet_name] has been generated.\n";
    };

    my $ofg_tag_type = sub {

        #@type MongoDB::Collection
        my $coll = $db->get_collection('ofgsw');
        my $exists = $coll->count( { 'gc.cv' => { '$exists' => 1 } } );
        if ( !$exists ) {
            print "    ofgsw.gc.cv doesn't exist\n";
            print "    Skip sheets ofg_tag_type\n";
            return;
        }

        my $write_sheet = sub {
            my ( $by, $bind ) = @_;

            my $sheet_name;
            if ( $by eq "tag" ) {
                $sheet_name = "ofg_tag_$bind";
            }
            elsif ( $by eq "type" ) {
                $sheet_name = "ofg_type_$bind";
            }
            elsif ( $by eq "tt" ) {
                $sheet_name = "ofg_tt_$bind";
            }

            # length limit of excel sheet names
            $sheet_name = substr $sheet_name, 0, 31;
            my $sheet;
            $toxlsx->row(0);
            $toxlsx->column(0);

            my @names = qw{_id AVG_gc AVG_cv AVG_pos COUNT};
            {    # header
                $sheet = $toxlsx->write_header( $sheet_name, { header => \@names } );
            }

            my $data = [];
            push @{$data}, [] for @names;
            {    # content

                my $condition;
                if ( $by eq "tag" ) {
                    $condition = { 'ofg.distance' => { '$lte' => 15 }, 'ofg.tag' => $bind, };
                }
                elsif ( $by eq "type" ) {
                    $condition = { 'ofg.distance' => { '$lte' => 15 }, 'ofg.type' => $bind, };
                }
                elsif ( $by eq "tt" ) {
                    my ( $tag, $type ) = split /\-/, $bind;
                    $condition = {
                        'ofg.distance' => { '$lte' => 20 },
                        'ofg.tag'      => $tag,
                        'ofg.type'     => $type,
                    };
                }

                my @docs = $coll->aggregate(
                    [   { '$match' => $condition },
                        {   '$group' => {
                                $names[0] => '$ofg.distance',
                                $names[1] => { '$avg' => '$gc.gc' },
                                $names[2] => { '$avg' => '$gc.cv' },
                                $names[3] => { '$avg' => '$pos_count' },
                                $names[4] => { '$sum' => 1 },
                            }
                        },
                        { '$sort' => { $names[0] => 1 } },
                    ]
                )->all;
                for my $row (@docs) {
                    for my $i ( 0 .. $#names ) {
                        push @{ $data->[$i] }, $row->{ $names[$i] };
                    }
                }
                $sheet->write( $toxlsx->row, 0, $data, $toxlsx->format->{NORMAL} );
            }

            if ( $opt->{chart} ) {    # chart
                $chart_gc_cv->( $sheet, $data, "Distance to ofg" );
            }

            print "Sheet [$sheet_name] has been generated.\n";
        };

        my $ary_ref;
        if ( $opt->{by} eq "tag" ) {
            $ary_ref = get_tags($db);
        }
        elsif ( $opt->{by} eq "type" ) {
            $ary_ref = get_types($db);
        }
        elsif ( $opt->{by} eq "tt" ) {
            $ary_ref = get_tts($db);
        }

        for ( @{$ary_ref} ) {
            $write_sheet->( $opt->{by}, $_ );
        }
    };

    #----------------------------------------------------------#
    # Run
    #----------------------------------------------------------#
    {
        &$distance_to_trough;
        &$distance_to_crest;
        &$gradient;
        &$ofg_all;
        &$ofg_tag_type;
    }

    if ( $opt->{index} ) {
        $toxlsx->add_index_sheet;
        print "Sheet [INDEX] has been generated.\n";
    }

    $stopwatch->end_message( "", "duration" );
}

#----------------------------------------------------------#
# Subroutines
#----------------------------------------------------------#
sub get_tags {

    #@type MongoDB::Database
    my $db = shift;

    my $result = $db->run_command(
        [   "distinct" => "ofg",
            "key"      => "tag",
            "query"    => {},
        ]
    );
    my @values = sort @{ $result->{values} };

    return \@values;
}

sub get_types {

    #@type MongoDB::Database
    my $db = shift;

    my $result = $db->run_command(
        [   "distinct" => "ofg",
            "key"      => "type",
            "query"    => {},
        ]
    );
    my @values = sort @{ $result->{values} };

    return \@values;
}

sub get_tts {

    #@type MongoDB::Database
    my $db = shift;

    #@type MongoDB::Collection
    my $coll = $db->get_collection('ofg');

    my @results
        = $coll->aggregate( [ { '$group' => { "_id" => { type => '$type', tag => '$tag' } } } ] )
        ->all;

    #    print YAML::Syck::Dump \@results;

    my @values;
    for (@results) {
        my $hash_ref = $_->{_id};
        push @values, $hash_ref->{tag} . '-' . $hash_ref->{type};
    }
    @values = sort @values;

    return \@values;
}

1;
