#!/bin/bash
#shellcheck disable=SC2086
#
#  Build and push the docker container
#
version=$(git rev-parse --short HEAD)
image_tag=canarymonitor/agent:$version

make release
docker tag agent:$version $image_tag
docker push $image_tag

# `latest` is what the Helm chart uses by default.
latest_tag=canarymonitor/agent:latest
docker tag $image_tag $latest_tag
docker push $latest_tag

cat <<EOF

Build data:

`cat priv/build.txt`

EOF
