#!/usr/bin/env bash
#
# The C# monitor runner is loaded from S3 during build time so we don't
# have to check it in.
#
set -euo pipefail

if [ "$#" -ne 0 ]
then
    github_ref=$1
else
    github_ref=""
fi

case "$github_ref" in
    refs/heads/main)
        qualifier=""
        ;;
    *)
        qualifier="-preview"
        ;;
esac

echo "Using GITHUB_REF $github_ref and qualifier $qualifier"

dist=https://monitor-distributions.metrist.io

latest=$(curl $dist/runner-latest$qualifier.txt)
echo "Installing runner version $latest"
curl $dist/runner-${latest}-linux-x64.zip >/tmp/runner.zip
rm -rf priv/runner
mkdir -p priv/runner
cd priv/runner
unzip /tmp/runner.zip
