#!/usr/bin/env bash

set -e

dist=$1
ver=$2
base=$(cd $(dirname $0); /bin/pwd)
tag=$ver-$(date +%Y.%W)
image=public.ecr.aws/metrist/dist-$dist

cd "$base/$dist/$ver"

docker build -t $image:$tag .
docker tag $image:$tag $image:$ver-latest
docker push $image:$tag
docker push $image:$ver-latest
