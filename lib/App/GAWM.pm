package App::GAWM;
use 5.010001;
use strict;
use warnings;
use App::Cmd::Setup -app;

our $VERSION = "0.0.5";

1;

__END__

=encoding utf-8

=head1 NAME

App::GAWM - Genome Analyst with MongoDB

=head1 SYNOPSIS

    gawm <command> [-?h] [long options...]
        -? -h --help    show help

    Available commands:

      commands: list the application's commands
          help: display a command's help screen

         count: add position files and count intersections
        gcwave: add GC ralated tables
           gen: generate database from fasta files
          init: check, drop (initiate), dump or restore MongoDB
      position: add position files to ofg and generate ofgsw
          stat: do stats on gawm databases
          swcv: update CV for ofgsw and gsw

See C<gawm commands> for usage information.

=head1 DESCRIPTION

App::GAWM is ...

=head1 AUTHOR

Qiang Wang E<lt>wang-q@outlook.comE<gt>

=head1 LICENSE

This software is copyright (c) 2017 by Qiang Wang.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
