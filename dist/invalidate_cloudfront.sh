#!/usr/bin/env bash

set -eo pipefail

echo "Invalidating cloudfront Orchestrator distributions"

aws cloudfront create-invalidation --distribution-id E1FRDOED06X2I8 --paths "/orchestrator/$dist/*" --no-cli-pager
