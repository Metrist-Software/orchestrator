#!/bin/bash
set -e

SERVICE="metrist-orchestrator.service"

systemctl daemon-reload
systemctl stop $SERVICE
