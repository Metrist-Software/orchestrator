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
	docker build -t agent:`git rev-parse --short HEAD` --build-arg GITHUB_REF=`git rev-parse --symbolic-full-name HEAD` .

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

exec_dev: exec_help
	aws ecs execute-command --region=us-east-1 --command /bin/bash --interactive --container orchestrator --cluster default --task \
	    `aws ecs list-tasks --region=us-east-1 --service-name=orchestrator-dev1-OrchestratorService | jq '.taskArns[0]' | cut -d/ -f3 | sed 's/"//'`
exec_prod: exec_help
	aws ecs execute-command --region=us-west-2 --command /bin/bash --interactive --container orchestrator --cluster default --task \
	    `aws ecs list-tasks --region=us-west-2 --service-name=orchestrator-prod-OrchestratorService | jq '.taskArns[0]' | cut -d/ -f3 | sed 's/"//'`

exec_help:
	@echo
	@echo
	@echo "   Use './orchestrator --bw-command remote' to get an IEx shell once connected"
	@echo
	@echo "   On the IEx prompt, use ':observer_cli.start()' to get to the console observer"
	@echo
