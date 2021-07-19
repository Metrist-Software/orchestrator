#!/usr/bin/env bash
#
# The C# monitor runner is loaded from S3 during build time so we don't
# have to check it in.
#
set -euo pipefail

latest=$(curl https://assets.canarymonitor.com/dist/monitors/latest.txt)
echo "Installing runner version $latest"
curl https://assets.canarymonitor.com/dist/monitors/runner-${latest}-linux-x64.zip >/tmp/runner.zip
cd priv/runner
unzip /tmp/runner.zip
