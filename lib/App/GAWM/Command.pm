package App::GAWM::Command;
use strict;
use warnings;

use App::Cmd::Setup -command;

sub opt_spec {
    my ( $class, $app ) = @_;
    return (
        [ 'server=s', 'MongoDB server IP/Domain name', { default => "localhost" } ],
        [ 'port=i',   'MongoDB server IP/Domain name', { default => "27017" } ],
        [ 'db|d=s',   'MongoDB database name',         { default => "gawm" } ],
        $class->options($app),
    );
}

1;

__END__

=pod

=cut
