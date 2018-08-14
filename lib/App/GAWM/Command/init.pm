package App::GAWM::Command::init;
use strict;
use warnings;
use autodie;

use App::GAWM -command;
use App::GAWM::Common;

sub abstract {
    return 'check, drop (initiate), dump or restore MongoDB';
}

sub opt_spec {
    return (
        [ 'host=s', 'MongoDB server IP/Domain name', { default => "localhost" } ],
        [ 'port=i', 'MongoDB server port',           { default => "27017" } ],
        [ 'db|d=s', 'MongoDB database name',         { default => "gawm" } ],
        [],
        [ "dir=s", "dump to/restore from directory" ],
        { show_defaults => 1, }
    );
}

sub usage_desc {
    return "gawm init <action> [options]";
}

sub description {
    my $desc;
    $desc .= ucfirst(abstract) . ".\n";
    $desc .= "List of actions:\n";
    $desc .= "\tcheck:   a running MongoDB service and path/to/mongodb/bin in \$PATH\n";
    $desc .= "\tdrop:    drops the database for accepting new data\n";
    $desc .= "\tdump:    export of the contents of the database \n";
    $desc .= "\trestore: restore a database from a binary database dump\n";
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

    if ( $args->[0] eq "dump" or $args->[0] eq "restore" ) {
        if ( $opt->{dir} ) {
            if ( !Path::Tiny::path( $opt->{dir} )->is_dir ) {
                $self->usage_error("The directory [$opt->{dir}] doesn't exist.");
            }
        }
        else {
            $self->usage_error("Actions dump and restore need --dir.");
        }
    }
    elsif ( $args->[0] eq "check" or $args->[0] eq "drop" ) {    # just OK
    }
    else {
        $self->usage_error("Action [$args->[0]] is invalid.");
    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $stopwatch = AlignDB::Stopwatch->new;
    $stopwatch->start_message();

    my $server = sprintf "--host %s --port %d", $opt->{host}, $opt->{port};

    if ( $args->[0] eq "check" ) {
        if ( IPC::Cmd::can_run("mongo") ) {
            print "*OK*: find [mongo] in \$PATH\n";
        }
        else {
            print "*Failed*: can't find [mongo] in \$PATH\n";
            exit 1;
        }

        my $cmd = qq{mongo $opt->{db} $server --eval "print(db.getMongo());"};
        if ( system($cmd) == 0 ) {
            print "*OK*: successfully connect to [$server]\n";
        }
        else {
            print "*Failed*: system [$cmd] failed\n";
            exit 1;
        }
    }
    elsif ( $args->[0] eq "drop" ) {
        my $cmd = qq{mongo $opt->{db} $server --eval "db.dropDatabase();"};
        if ( system($cmd) == 0 ) {
            print "*OK*: system [$cmd]\n";
        }
        else {
            print "*Failed*: system [$cmd]\n";
            exit 1;
        }
    }
    elsif ( $args->[0] eq "dump" ) {
        my $cmd = qq{mongodump $server --db $opt->{db} --out $opt->{dir}};
        if ( system($cmd) == 0 ) {
            print "*OK*: system [$cmd]\n";
        }
        else {
            print "*Failed*: system [$cmd]\n";
            exit 1;
        }
    }
    elsif ( $args->[0] eq "restore" ) {
        my $cmd = qq{mongorestore $opt->{dir} $server --db $opt->{db}};
        print "Run [$cmd]\n";
        if ( system($cmd) == 0 ) {
            print "*OK*: system [$cmd]\n";
        }
        else {
            print "*Failed*: system [$cmd]\n";
            exit 1;
        }
    }

    $stopwatch->end_message();
}

1;
