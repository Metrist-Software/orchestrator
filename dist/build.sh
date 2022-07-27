#!/usr/bin/env bash
#
#  Run a build through docker. The actual build steps are in do-build.sh


dist=$1
ver=$2
base=$(cd $(dirname $0); /bin/pwd)
# TODO use the date-stamped image
image=public.ecr.aws/metrist/dist-$dist:$ver-latest
cd $base/..
rm -rf _build dep

docker run -v $PWD:$PWD --user $UID $image $base/do-build.sh $PWD $dist $ver
