#!/usr/bin/env bash
#
#  Execute something for all distributions.
#
set -e

set -vx

cd "$(dirname $0)"

# Find all distribution directories, which is two levels deep.
ls -ld */* |
    grep ^d |
    awk '{print $9}' |
    sed 's,/, ,' |
    while read -r dist ver; do
    $1 $dist $ver
done
