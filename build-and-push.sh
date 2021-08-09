#!/bin/bash
#shellcheck disable=SC2086
#
#  Build and push the docker container
#
version=$(git rev-parse --short HEAD)
image_tag=canarymonitor/agent:$version

# Note that this'll for now build "orchestrator" which we then
# tag as agent and push under that name (transitionally).
make release
docker tag orchestrator:$version $image_tag
docker push $image_tag

# This is what the Helm chart uses by default.
latest_tag=canarymonitor/agent:latest
docker tag $image_tag $latest_tag
docker push $latest_tag

cat <<EOF

Build data:

`cat priv/build.txt`

EOF
