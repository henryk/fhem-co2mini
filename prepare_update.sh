#!/bin/bash
CONTROL=controls_co2mini.txt
DIRS="./FHEM"

rm $CONTROL

# From https://github.com/nesges/Widgets-for-fhem-tablet-ui/blob/master/prepare_update.sh

find $DIRS -type f \( ! -iname ".*" \) -print0 | while IFS= read -r -d '' f; 
    do
        out="UPD `stat --format "%z %s" $f | sed -e "s#\([0-9-]*\)\ \([0-9:]*\)\.[0-9]*\ [+0-9]*#\1_\2#"` $f"
        echo ${out//.\//} >> $CONTROL
    done

# CHANGED file
git log --date=short "--format=format:%ad%n - %s" $DIRS > CHANGED
