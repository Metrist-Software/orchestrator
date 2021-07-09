#!/usr/bin/env bash
#
# The C# monitor runner is loaded from S3 during build time so we don't
# have to check it in.
#
set -euo pipefail

latest=$(curl https://canary-public-assets.s3.us-west-2.amazonaws.com/dist/monitors/latest.txt)
curl https://canary-public-assets.s3.us-west-2.amazonaws.com/dist/monitors/runner-0.0.1-0f3dedb7-linux-x64.zip >/tmp/runner.zip
cd priv/runner
unzip /tmp/runner.zip
