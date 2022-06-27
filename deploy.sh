#!/bin/bash
#
#  Deploy using Stackery.
#
#  We use "GITHUB_REF" as the indicator of a CI or a local deploy.
#
set -eo pipefail # For safety
set -vx          # For debugging

declare -A env_tag_aws_region
env_tag_aws_region=(
  ["dev1"]="us-east-1"
  ["prod"]="us-west-2"
  ["prod2"]="us-east-2"
  ["prod-mon-us-east-1"]="us-east-1"
  ["prod-mon-us-west-1"]="us-west-1"
  ["prod-mon-ca-central-1"]="ca-central-1"
)

local_deploy=""
if [ -z "$GITHUB_REF" ]; then
  local_deploy=true
  GITHUB_REF=local
fi

if [ ! -v DEPLOY_ENVIRONMENT ]; then
  case $GITHUB_REF in
  refs/heads/main)
    DEPLOY_ENVIRONMENT=prod
    ;;
  refs/heads/develop | local)
    DEPLOY_ENVIRONMENT=dev1
    ;;
  *)
    echo "Unknown branch $GITHUB_REF, not deploying"
    exit 0
    ;;
  esac
fi

container_tag=$(git rev-parse --short HEAD)

# Set up templates
out_basepath=$(mktemp -d -t orchestrator-XXXX)
for env in "${!env_tag_aws_region[@]}"; do
  sed "s/<EnvironmentName>/$env/g" orchestrator.yaml >"${out_basepath}/orchestrator-${env}.yaml"
done

# Deploy
case $DEPLOY_ENVIRONMENT in
dev1)
  aws cloudformation deploy \
    --template-file "${out_basepath}/orchestrator-dev1.yaml" \
    --stack-name "orchestrator-dev1" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides ContainerVersion=$container_tag \
    --region ${env_tag_aws_region[dev1]}
  ;;
prod)
  # Orchestrator runs everywhere that monitors run.
  for env in prod prod2 prod-mon-us-east-1 prod-mon-us-west-1 prod-mon-ca-central-1; do
    aws cloudformation deploy \
      --template-file "${out_basepath}/orchestrator-${env}.yaml" \
      --stack-name "orchestrator-${env}" \
      --capabilities CAPABILITY_NAMED_IAM \
      --region ${env_tag_aws_region["$env"]} \
      --parameter-overrides ContainerVersion=$container_tag &
  done
  wait
  ;;
esac

# This is for GCP and hopefully at some point in time also for AWS. Maybe there is duplication
# with the code above, but that's so that we can just throw away everything and keep just this
# bit here.
#

case "${GITHUB_REF:-}" in
    refs/heads/main)
        qualifier=""
        ;;
    *)
        qualifier="-preview"
        ;;
esac

version=$(git rev-parse --short HEAD)
image_tag=canarymonitor/agent:$version

tag_file=orchestrator-latest$qualifier.txt
echo $image_tag >/tmp/$tag_file
aws s3 cp --region=us-west-2 /tmp/$tag_file s3://canary-private/version-stamps/$tag_file
