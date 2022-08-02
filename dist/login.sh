#!/usr/bin/env bash
#
#  How to login to ECR, which is where we distribute the official
#  build images and the orchestrator container.

aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
