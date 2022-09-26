#!/usr/bin/env bash
#
#  Refresh base containers. This is supposed to run once a week.
#
set -euo pipefail
set -vx

tag=base-$(date +%Y.%W)
image=public.ecr.aws/metrist/orchestrator

# Bump all refreshed-at timestamps to force a full rebuild.
TS=$(TZ=Zulu date +%Y%m%dT%H%M%SZ)
DOCKERFILES=$(find . -name 'Dockerfile*')
sed -i "s,\(ENV REFRESHED_AT\).*,\1 $TS," $DOCKERFILES
git commit -m "Bump refresh to ${TS}" $DOCKERFILES

# Refresh base containers for building docker release
for i in build runtime
do
    full_version=$image:${i}-${tag}
    docker build -f Dockerfile.${i}-base -t $full_version .
    docker push $full_version
done
sed -Ei "s/-base-[0-9]{4}\.[0-9]+/-${tag}/" Dockerfile
git commit -m "Bump base tag to ${tag}" Dockerfile

# Refresh base containers for building OS releases
dist/for-all.sh dist/build-base.sh

git push
