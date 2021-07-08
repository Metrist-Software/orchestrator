#!/bin/bash
#shellcheck disable=SC2086
#
#  Build and push the docker container
#
ecr_name=147803588724.dkr.ecr.us-west-2.amazonaws.com
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ecr_name
version=$(git rev-parse --short HEAD)
image_tag=$ecr_name/orchestrator:$version

make release
docker tag orchestrator:$version $image_tag
docker push $image_tag

# This is strictly not needed, but _might_ come in handy when testing.
latest_tag=$ecr_name/orchestrator:latest
docker tag $image_tag $latest_tag
docker push $latest_tag

cat <<EOF

Build data:

`cat priv/build.txt`

EOF
