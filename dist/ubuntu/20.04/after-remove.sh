#!/bin/bash
set -e

SERVICE="metrist-orchestrator.service"

if systemctl is-enabled --quiet $SERVICE; then
  systemctl stop $SERVICE
  systemctl disable $SERVICE
  systemctl reset-failed $SERVICE
  systemctl daemon-reload
fi

