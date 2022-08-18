#!/bin/bash
#
#  "Deploy" - we just update the version stamp file in S3 and let the pull-based
#  process on the orchestrator instances do the rest.
#
#  We use "GITHUB_REF" as the indicator of a CI or a local deploy.
#
set -eo pipefail # For safety
set -vx          # For debugging

case "${GITHUB_REF:-}" in
    refs/heads/main)
        qualifier=""
        ;;
    *)
        qualifier="-preview"
        ;;
esac

version=$(git rev-parse --short HEAD)
image_tag=public.ecr.aws/metrist/orchestrator:$version

tag_file=orchestrator-latest$qualifier.txt
echo $image_tag >/tmp/$tag_file
aws s3 cp --region=us-west-2 /tmp/$tag_file s3://metrist-private/version-stamps/$tag_file
