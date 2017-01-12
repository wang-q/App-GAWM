package App::GAWM::Command::init;
use strict;
use warnings;
use autodie;

use App::GAWM -command;
use App::GAWM::Common;

use constant abstract => 'check, drop (initiate), dump or restore MongoDB';

sub opt_spec {
    return ( [ "dir=s", "dump to/restore from directory" ], { show_defaults => 1, } );
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

}

1;
