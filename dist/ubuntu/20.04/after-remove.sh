#!/bin/bash

set -ex

if systemctl is-enabled --quiet metrist-orchestrator; then
  systemctl stop metrist-orchestrator
  systemctl disable metrist-orchestrator
  systemctl reset-failed
  systemctl daemon-reload
fi

