[![Build Status](https://travis-ci.org/wang-q/App-GAWM.svg?branch=master)](https://travis-ci.org/wang-q/App-GAWM) [![Coverage Status](http://codecov.io/github/wang-q/App-GAWM/coverage.svg?branch=master)](https://codecov.io/github/wang-q/App-GAWM?branch=master) [![MetaCPAN Release](https://badge.fury.io/pl/App-GAWM.svg)](https://metacpan.org/release/App-GAWM)
# NAME

App::GAWM - Genome Analyst with MongoDB

# SYNOPSIS

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

See `gawm commands` for usage information.

# DESCRIPTION

App::GAWM is ...

# AUTHOR

Qiang Wang &lt;wang-q@outlook.com>

# LICENSE

This software is copyright (c) 2017 by Qiang Wang.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
