# Benchmarks on different versions of MongoDB

## Start MongoDB services

Install MongoDB by following
[this script](https://github.com/egateam/egavm/blob/master/prepare/standalone/4-mongodb.sh) and its
companions.

```bash
# mongodb26
rm ~/share/mongodb26/data/mongod.lock
~/share/mongodb26/bin/mongod --config ~/share/mongodb26/mongod.cnf

# mongodb30
rm ~/share/mongodb30/data/mongod.lock
~/share/mongodb30/bin/mongod --config ~/share/mongodb30/mongod.cnf

# mongodb40
rm ~/share/mongodb/data/mongod.lock
~/share/mongodb/bin/mongod --config ~/share/mongodb/mongod.cnf
```

MongoDB 3.0.7 has a bug on `mongorestore`. Don't use this version.

## Command lines of tests

```bash
# need a working MongoDB to pass tests
cpanm https://github.com/wang-q/App-GAWM.git

mkdir -p ~/data/dumps/mongodb/

export GAWM_PARALLEL=4

gawm init check

#----------------------------#
# gcwave
#----------------------------#
gawm init drop -d Atha_GC

# 257: db.getCollection('align').count({})
gawm gen -d Atha_GC -n Atha \
    --dir ~/data/alignment/Ensembl/Atha/ \
    --length 500000 --parallel $GAWM_PARALLEL

gawm gcwave -d Atha_GC --batch 10 --parallel $GAWM_PARALLEL

rm -fr ~/data/dumps/mongodb/Atha_GC
gawm init dump -d Atha_GC --dir ~/data/dumps/mongodb/

gawm swcv -d Atha_GC --batch 10 --parallel $GAWM_PARALLEL

gawm stat -d Atha_GC --chart

#----------------------------#
# T-DNA ofgsw
#----------------------------#
gawm init drop -d Atha_TDNA_SW

gawm gen -d Atha_TDNA_SW -n Atha \
    --dir ~/data/alignment/Ensembl/Atha/ \
    --length 500000 --parallel $GAWM_PARALLEL

gawm position -d Atha_TDNA_SW --batch 10 --parallel $GAWM_PARALLEL \
    --style center \
    --tag tdna --type CSHL --file ~/data/salk/Atha/T-DNA.CSHL.pos.txt \
    --tag tdna --type FLAG --file ~/data/salk/Atha/T-DNA.FLAG.pos.txt \
    --tag tdna --type MX   --file ~/data/salk/Atha/T-DNA.MX.pos.txt   \
    --tag tdna --type RATM --file ~/data/salk/Atha/T-DNA.RATM.pos.txt

gawm stat -d Atha_TDNA_SW --by type --chart --replace "ofg=insert sites"

#----------------------------#
# gsw count
#----------------------------#
gawm init drop -d Atha_GC_TDNA
gawm init restore --dir ~/data/dumps/mongodb/Atha_GC --db Atha_GC_TDNA

gawm count insert -d Atha_GC_TDNA --batch 10 --parallel $GAWM_PARALLEL \
    --file ~/data/salk/Atha/T-DNA.CSHL.pos.txt \
    --file ~/data/salk/Atha/T-DNA.FLAG.pos.txt \
    --file ~/data/salk/Atha/T-DNA.MX.pos.txt   \
    --file ~/data/salk/Atha/T-DNA.RATM.pos.txt

gawm count count -d Atha_GC_TDNA --batch 10 --parallel $GAWM_PARALLEL

gawm stat -d Atha_GC_TDNA --by type --chart

unset GAWM_PARALLEL
```

## Results

* 4 threads: macOS 10.13, i7-6700k, 32G, SSD

    |        |   step   |  2.6.12 |  3.0.14 |   3.4.1 |   4.0.1 |
    |:------:|:--------:|--------:|--------:|--------:|--------:|
    | gcwave |   gen    |     9'' |     9'' |    13'' |    12'' |
    |        |  gcwave  | 10'52'' | 10'53'' | 10'38'' | 10'52'' |
    |        |   dump   |     1'' |     3'' |     8'' |     3'' |
    |        |   swcv   | 41'19'' | 40'55'' | 41'10'' | 40'50'' |
    |        |   stat   |         |    12'' |    10'' |    11'' |
    | ofgsw  | position |  5'16'' |  4'58'' |  4'50'' |  5'22'' |
    |        |   stat   |    21'' |    27'' |    22'' |    26'' |
    | count  | restore  |    49'' |    33'' |    30'' |    32'' |
    |        |  insert  |    54'' |    58'' |    56'' |  1'36'' |
    |        |  count   |  1'56'' |  1'56'' |  1'56'' |  1'51'' |
    |        |   stat   |     8'' |    11'' |     9'' |    10'' |

* 12 threads: Ubuntu 14.04, E5-2690 v3 x 2, 128G, HDD

    |        |   step   |  2.6.12 | 3.0.14 |   3.4.1 |
    |:------:|:--------:|--------:|-------:|--------:|
    | gcwave |   gen    |    12'' |   11'' |    11'' |
    |        |  gcwave  |  5'38'' | 5'19'' |  5'14'' |
    |        |   dump   |     5'' |    6'' |    18'' |
    |        |   swcv   | 21'24'' | 20'8'' | 20'17'' |
    |        |   stat   |     9'' |   12'' |    11'' |
    | ofgsw  | position |  4'27'' | 4'15'' |   4'9'' |
    |        |   stat   |    21'' |   22'' |    22'' |
    | count  | restore  |    44'' |   46'' |    40'' |
    |        |  insert  |    51'' |   53'' |    49'' |
    |        |  count   |  1'58'' |  1'9'' |  1'11'' |
    |        |   stat   |    10'' |   10'' |     9'' |

* disk usages

    * mac

        ```
        $ du -hs ~/share/mongodb*
        1.5G	/Users/wangq/share/mongodb
         11G	/Users/wangq/share/mongodb26
        1.9G	/Users/wangq/share/mongodb30
        ```

    * Ubuntu

        ```
        $ du -hs ~/share/mongodb*
        1.7G    /home/wangq/share/mongodb
        11G     /home/wangq/share/mongodb26
        1.7G    /home/wangq/share/mongodb30
        ```

* different number of threads, MongoDB 3.4.1

    * macOS: 4

    * Ubuntu: 4, 8, 12, and 16

    |        |   step   |     mac |       4 |       8 |      12 |     16 |
    |:------:|:--------:|--------:|--------:|--------:|--------:|-------:|
    | gcwave |  gcwave  | 10'38'' | 12'34'' |   7'4'' |  5'14'' | 4'32'' |
    |        |   swcv   | 41'10'' | 49'11'' | 27'14'' | 20'17'' | 17'9'' |
    | ofgsw  | position |  4'50'' |  5'53'' |  4'29'' |   4'9'' | 3'58'' |
    | count  |  insert  |    56'' |    51'' |    47'' |    49'' |   49'' |
    |        |  count   |  1'56'' |  2'36'' |  1'39'' |  1'11'' |   48'' |
