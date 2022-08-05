#!/usr/bin/env bash
#
#  Run a build through docker. The actual build steps are in do-build.sh

set -e

set -vx

dist=$1
ver=$2
base=$(cd $(dirname $0); /bin/pwd)
# TODO use the date-stamped image
image=public.ecr.aws/metrist/dist-$dist:$ver-latest
cd $base/..
rm -rf _build dep

docker run -v $PWD:$PWD --user $UID $image $base/do-build.sh $PWD $dist $ver

pkg=$(cat pkg/$dist-$ver)

gpg --sign --armor --detach-sign pkg/$pkg

aws s3 cp pkg/$pkg s3://dist.metrist.io/orchestrator/$dist/
aws s3 cp pkg/$pkg.asc s3://dist.metrist.io/orchestrator/$dist/
aws s3 rm s3://dist.metrist.io/orchestrator/$dist/$dist-$ver.latest.txt
echo $pkg | aws s3 cp - s3://dist.metrist.io/orchestrator/$dist/$dist-$ver.latest.txt
