#!/usr/bin/env bash
#
# The C# monitor runner is loaded from S3 during build time so we don't
# have to check it in.
#
set -euo pipefail

# TODO once the S3 upload invalidates CloudFront, make this point there
dist=https://canary-public-assets.s3.us-west-2.amazonaws.com/dist/monitors

latest=$(curl $dist/latest.txt)
echo "Installing runner version $latest"
curl $dist/runner-${latest}-linux-x64.zip >/tmp/runner.zip
cd priv/runner
unzip /tmp/runner.zip
