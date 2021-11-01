#!/bin/bash
#
#  Deploy using Stackery.
#
#  We use "GITHUB_REF" as the indicator of a CI or a local deploy.
#
set -eo pipefail # For safety
set -vx          # For debugging

declare -A env_tag_aws_region
env_tag_aws_region["dev1"]="us-east-1"
env_tag_aws_region["prod"]="us-west-2"
env_tag_aws_region["prod2"]="us-east-2"
env_tag_aws_region["prod-mon-us-east-1"]="us-east-1"
env_tag_aws_region["prod-mon-us-west-1"]="us-west-1"
env_tag_aws_region["prod-mon-ca-central-1"]="ca-central-1"

local_deploy=""
if [ -z "$GITHUB_REF" ]; then
  local_deploy=true
  GITHUB_REF=local
fi

if [ ! -v STACKERY_ENVIRONMENT ]; then
  case $GITHUB_REF in
  refs/heads/main)
    STACKERY_ENVIRONMENT=prod
    ;;
  refs/heads/develop | local | refs/heads/929*)
    STACKERY_ENVIRONMENT=dev1
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
case $STACKERY_ENVIRONMENT in
dev1)
  parameter_overrides=""
  if [ -z "$local_deploy" ]; then
    parameter_overrides="--parameter-overrides ParameterKey=ContainerVersion,ParameterValue=$container_tag"
  else
    echo aws ssm --name "/dev1/orchestrator/container/version" \
      --value container_tag
  fi

  echo aws cloudformation deploy \
    --template-file "${out_basepath}/orchestrator-dev1.yaml" \
    --stack-name "orchestrator-dev1" $parameter_overrides \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${env_tag_aws_region["dev1"]} \
    --no-execute-changeset
  ;;
prod)
  for env in prod prod2 prod-mon-us-east-1 prod-mon-us-west-1 prod-mon-ca-central-1; do
    echo aws ssm --name "/${env}/orchestrator/container/version" \
      --value container_tag
    echo aws cloudformation deploy \
      --template-file "${out_basepath}/orchestrator-${env}.yaml" \
      --stack-name "orchestrator-${env}" \
      --capabilities CAPABILITY_NAMED_IAM \
      --region ${env_tag_aws_region["$env"]} \
      --no-execute-changeset &
  done
  wait
  ;;
esac
