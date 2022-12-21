#!/bin/bash

set -ex

if systemctl is-enabled --quiet metrist-orchestrator; then
  systemctl stop metrist-orchestrator
fi

systemctl daemon-reload

