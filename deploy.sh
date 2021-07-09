#!/bin/bash
#
#  Deploy using Stackery.
#
#  We use "GITHUB_REF" as the indicator of a CI or a local deploy.
#
set -eo pipefail # For safety
set -vx # For debugging

local_deploy=""
if [ -z "$GITHUB_REF" ]
then
  local_deploy=true
  GITHUB_REF=local
fi

if [ -z "$local_deploy" ]
then
  curl -Ls --compressed https://ga.cli.stackery.io/linux/stackery > /tmp/stackery
  chmod +x /tmp/stackery
  stackery=/tmp/stackery
else
  stackery=$(which stackery)
fi

if [ ! -v STACKERY_ENVIRONMENT ]
then
  case $GITHUB_REF in
    refs/heads/main)
      STACKERY_ENVIRONMENT=prod
      ;;
    refs/heads/develop|local|refs/heads/929*)
      STACKERY_ENVIRONMENT=dev1
      ;;
    *)
      echo "Unknown branch $GITHUB_REF, not deploying"
      exit 0
      ;;
  esac
fi

container_tag=$(git rev-parse --short HEAD)
if [ -z "$local_deploy" ]
then
  $stackery env parameters set --env-name=$STACKERY_ENVIRONMENT orchestrator.container.version $container_tag
  template_arg=""
else
  sed "s/\${ContainerVersion}/$container_tag/" <orchestrator.yaml >/tmp/orchestrator.yaml
  template_arg="-t /tmp/orchestrator.yaml"
fi

if [ -n "$STACKERY_ENVIRONMENT" ]
then
  if [ -z "$local_deploy" ]
  then
    aws_args="--secret-access-key $AWS_SECRET_ACCESS_KEY --access-key-id $AWS_ACCESS_KEY_ID"
    ref="-r $GITHUB_REF"
  else
    ref="--strategy local"
  fi
  $stackery deploy -n orchestrator $template_arg $ref -e $STACKERY_ENVIRONMENT $aws_args

  # Orchestrator runs everywhere that monitors run.
  if [ $STACKERY_ENVIRONMENT = "prod" ]
  then
    for env in prod2 prod-mon-us-east-1 prod-mon-us-west-1 prod-mon-ca-central-1
    do
      $stackery env parameters set --env-name=$env orchestrator.container.version $container_tag
      $stackery deploy -n orchestrator $template_arg $ref -e $env $aws_args
    done
  fi
fi
