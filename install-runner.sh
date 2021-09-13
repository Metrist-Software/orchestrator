#!/usr/bin/env bash
#
# The C# monitor runner is loaded from S3 during build time so we don't
# have to check it in.
#
set -euo pipefail

case "$GITHUB_REF" in
    refs/heads/main)
        qualifier=""
        ;;
    *)
        qualifier="-preview"
        ;;
esac

dist=https://monitor-distributions.canarymonitor.com

latest=$(curl $dist/runner-latest$qualifier.txt)
echo "Installing runner version $latest"
curl $dist/runner-${latest}-linux-x64.zip >/tmp/runner.zip
cd priv/runner
unzip /tmp/runner.zip
