.PHONY: dev run db.reset

dev:
	mix deps.get

run:
    # Note that this will run aganst wherever your AWS... env vars are pointed at
	iex -S mix

release:
	mkdir -p priv/
	echo Revision: `git rev-parse --short HEAD` >priv/build.txt
	echo Date: `date` >>priv/build.txt
	echo Build-Host: `hostname` >>priv/build.txt
	docker build -t agent:`git rev-parse --short HEAD` .

local_release:
	MIX_ENV=prod mix do compile, release --overwrite

tail_cma_log_dev:
	aws logs tail --region=us-east-1 --follow --since=0m /stackery/task/orchestrator-dev1-PrivateCMATask/logs

tail_cma_log_prod:
	aws logs tail --region=us-west-2 --follow --since=0m /stackery/task/orchestrator-prod-PrivateCMATask/logs

tail_log_dev:
	aws logs tail --region=us-east-1 --follow --since=0m /stackery/task/orchestrator-dev1-OrchestratorTask/logs

tail_log_prod:
	aws logs tail --region=us-west-2 --follow --since=0m /stackery/task/orchestrator-prod-OrchestratorTask/logs

# TODO proper container names, etc.
exec_dev:
	@echo "Use 'bin/orchestrator remote' to get an IEx shell once connected"
	aws ecs execute-command --region=us-east-1 --command /bin/sh --interactive --container orchestrator --cluster default --task \
	    `aws ecs list-tasks --region=us-east-1 --service-name=orchestrator-dev1-OrchestratorService | jq '.taskArns[0]' | cut -d/ -f3 | sed 's/"//'`
