#!/usr/bin/env bash
#
#  Build the code in $1 and tag it with distribution $2 and version $3
#
set -e
set -vx

ls
pwd
base=$(cd $1; /bin/pwd)
dist=$2
ver=$3
rel=$base/dist/$dist/$ver
tag=$(git rev-parse --short HEAD)

mix local.hex --force
mix local.rebar --force

cd $base
mix do deps.get, compile, release

dest=/tmp/pkg
[ -e $dest ] && rm -rf $dest
mkdir -p $dest

# Copy the binary over
mkdir -p $dest/usr/bin
cp _build/prod/rel/orchestrator/bin/orchestrator $dest/usr/bin

# Copy anything else we want to include over
(cd $rel/inc; cp -rv . $dest/)

cd $dest
fpm -s dir -t deb -n metrist-agent-$dist -v $ver-$tag .

# TODO upload to wherever.
