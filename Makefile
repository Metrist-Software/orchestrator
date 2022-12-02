.PHONY: dev run db.reset

dev:
	mix deps.get

run:
    # Note that this will run aganst wherever your AWS... env vars are pointed at
	iex -S mix

run_against_local:
	METRIST_API_HOST=localhost:4443 \
	METRIST_DISABLE_TLS_VERIFICATION=1  \
	METRIST_INSTANCE_ID=`hostname` \
	METRIST_API_TOKEN=fake-api-token-for-dev \
	METRIST_RUN_GROUPS=local-development \
	  iex -S mix

release:
	mkdir -p priv/
	echo Revision: `git rev-parse --short HEAD` >priv/build.txt
	echo Date: `date` >>priv/build.txt
	echo Build-Host: `hostname` >>priv/build.txt
	docker build -t orchestrator:`git rev-parse --short HEAD` --build-arg GITHUB_REF=`git rev-parse --symbolic-full-name HEAD` .

local_release:
	MIX_ENV=prod mix do compile, release --overwrite

tail_log_dev:
	aws logs tail --region=us-east-1 --follow --since=0m dev1-orchestrator-logs

tail_log_prod:
	aws logs tail --region=us-west-2 --follow --since=0m prod-orchestrator-logs
