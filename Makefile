.PHONY: dev run db.reset

dev:
	mix deps.get

run:
    # Note that this will run aganst wherever your AWS... env vars are pointed at
	iex -S mix

release:
	echo Revision: `git rev-parse --short HEAD` >assets/static/build.txt
	echo Date: `date` >>assets/static/build.txt
	echo Build-Host: `hostname` >>assets/static/build.txt
	docker build -t backend:`git rev-parse --short HEAD` .

local_release:
	MIX_ENV=prod mix do compile, release --overwrite

#tail_log_dev:
	#aws logs tail --region=us-east-1 --follow --since=0m /stackery/task/backend-dev1-BackendTask/logs

#tail_log_prod:
	#aws logs tail --region=us-west-2 --follow --since=0m /stackery/task/backend-prod-BackendTask/logs

#exec_dev:
	#@echo "Use 'bin/backend remote' to get an IEx shell once connected"
	#aws ecs execute-command --region=us-east-1 --command /bin/sh --interactive --container backend --cluster default --task \
	    #`aws ecs list-tasks --region=us-east-1 --service-name=backend-dev1-Service | jq '.taskArns[0]' | cut -d/ -f3 | sed 's/"//'`
