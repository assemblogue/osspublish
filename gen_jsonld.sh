#!/bin/bash
DIR=`mktemp -d`
for FILE in $*; do
    BASE=`basename $FILE`
    BASE="${BASE%.*}"
    (\
     libreoffice --headless --convert-to csv:"Text - txt - csv (StarCalc)":44,34,76,1,1 --outdir $DIR $FILE > /dev/null &&\
         sleep 1 &&\
            tr -d '\r' < $DIR/$BASE.csv > $DIR/$BASE.csv2 && \
            cat $DIR/$BASE.csv2 | perl ~/projects/plrv2/contentsdata/cto/cto.pl $DIR/$BASE $BASE && \
            cat $DIR/$BASE.csv2 | perl ~/projects/plrv2/contentsdata/cto/cts.pl $DIR/$BASE $BASE ) || exit 1
done
ls $DIR/*.jsonld
