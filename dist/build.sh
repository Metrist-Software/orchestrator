#!/usr/bin/env bash
#
#  Run a build through docker. The actual build steps are in do-build.sh
#
#  Arguments:
#  $1 - distribution name ('ubuntu')
#  $2 - version ('22.04')

set -e

set -vx

dist=$1
ver=$2

case "${GITHUB_REF:-}" in
    refs/heads/master)
        qualifier=""
        ;;
    *)
        qualifier="-preview"
        ;;
esac

base=$(cd $(dirname $0); /bin/pwd)
image=public.ecr.aws/metrist/dist-$dist:$ver-latest$qualifier
cd $base/..
rm -rf _build deps

docker run -v $PWD:$PWD --user $UID $image $base/do-build.sh $PWD $dist $ver

pkg=$(cat pkg/$dist-$ver)
arch=$(cat pkg/$dist-$ver.arch)

gpg --sign --armor --detach-sign pkg/$pkg

aws s3 cp pkg/$pkg s3://dist.metrist.io/orchestrator/$dist/
aws s3 cp pkg/$pkg.asc s3://dist.metrist.io/orchestrator/$dist/
echo $pkg | aws s3 cp - s3://dist.metrist.io/orchestrator/$dist/$ver.$arch.latest$qualifier.txt
