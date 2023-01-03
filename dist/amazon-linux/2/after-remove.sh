#!/bin/bash

set -ex

if systemctl is-failed --quiet metrist-orchestrator.service; then
  systemctl reset-failed metrist-orchestrator.service
fi

systemctl daemon-reload

