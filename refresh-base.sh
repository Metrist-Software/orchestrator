#!/usr/bin/env bash
#
#  Refresh base containers. This is supposed to run once a week.
#
set -euo pipefail

tag=base-$(date +%Y.%W)
image=public.ecr.aws/metrist/orchestrator

for i in build runtime
do
    full_version=$image:${i}-${tag}
    docker build -f Dockerfile.${i}-base -t $full_version .
    docker push $full_version
done

sed -Ei "s/-base-[0-9]{4}\.[0-9]+/-${tag}/" Dockerfile
git commit -m "Bump base tag to ${tag}" Dockerfile
git push
