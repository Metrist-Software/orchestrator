#!/bin/bash
set -x

SERVICE="metrist-orchestrator.service"

systemctl stop $SERVICE || true
systemctl reset-failed $SERVICE || true

systemctl daemon-reload

