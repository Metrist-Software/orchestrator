# Porting from AWS Lambda to direct DLL invocation

(and back, of course)

## Basic settings

The new Orchestrator can be controlled by a number of settings. The basic (always-needed) ones
are:

* `CANARY_API_HOST` decides where monitor configuration is downloaded and telemetry/error information is uploaded. For porting,
  set it to `app-dev1.canarymonitor.com`.
* `CANARY_API_TOKEN` decides "who we are". There are two possible values:
  1. `@secret@:/dev1/canary-internal/api-token#token` - this is a reference to the token for SHARED and to be used to port
     all monitors in that account;
  2. `@secret@:/dev1/private-cma/canary-api-token#token` - this is a reference to the token for the "private CMA" account,
     353-C in development;
* `CANARY_CLEANUP_ENABLED` should be set to 1.
* `CANARY_INVOCATION_STYLE` can be `awslambda` or `rundll`, during porting you want the latter.
* `CANARY_RUNDLL_LOCAL_PATH` is a pointer to the local copy of the monitor code. When set, downloads from S3 won't be attempted
  so it is very convenient to set it. For me, it is set to `../aws-serverless/shared`.

This is on top of things like AWS environment vars to actually read secrets, etcetera. One more thing is that you want a local
DLL runner copy, to do this, go into your Orchestrator dev dir and do:

    cd priv/runner
    ln -s ../../aws-serverless/shared/Canary.Shared.Monitoring.Runner/bin/Debug/netcoreapp3.1/* .

This will keep your DLL runner up-to-date in case you need to fix/recompile it (needless to say, but do this _after_ you have
done at least one `dotnet build` in there).

## Selecting what to run

Together with the API token, which selects the account, there is one env var for the selection of monitor configurations that
the instance receives:

* `CANARY_RUN_GROUPS` - this is your own unique run group, set it to `<your name>-development` or something like that.

## How development (dev1) is setup.

We run three Orchestrator instances in develop (and later in prod):

* One is the private CMA and we probably deal with that after everything else is over;
* One is the old style orchestrator - it runs with invocation style `awslambda` and run groups `"AWS Lambda"`. It is currently
  running all the monitors;
* The final one is the new style - it runs with invocation style `rundll` and run groups `"RunDLL"`. It is mostly idling (except
  for the test monitors I ported).

Therefore, the process is simple: just move every monitor from the old to the new run group.

## Process

1. Check that the monitor has a MonitorConfig that is just strings, that its (soon to be obsolete) `src/..../Function.cs` file is not
   doing anything smart - the monitor will be invoked directly without going through that call - and move anything from that file
   to the new `shared/.../Monitor.cs` home. Also check that the logical name matches the directory name (minus the uppercase) because
   that is for now mandatory. Tweak where needed.
1. Check that `Backend.Projections.Dbpa.MonitorConfig` will return the correct value for the `checks` function for the monitor. Should
   be all there but typos can and will happen.
1. Check that `Mix.Tasks.Canary.SecretsToConfig` is correct for your monitor. There is plenty of sample code there, and we want to not
   only copy actual secrets but also make sure that `extra_config` values in the monitor config have everything the monitor needs.
1. Run the mix task and verify in pgAdmin that all is well.
1. Your monitor can now run as DLL. Move it from the "AWS Lambda" run group to whatever you set for the local run group using the
   backend mix task `mix canary.set_run_group`. If you start Orchestrator (or have it running) using `iex -S mix` then when the next
   run is due, your local orchestrator should pick it up and the "AWS Lambda" orchestrator will stop running it (you can keep the
   Orchestrator run). Check that all is fine, telemetry is reported, etcetera.
1. If this works, then you should be done. Make sure that any monitor changes are on `develop` (and on the ticket 1212 branch as well!)
   and push; as soon as the DLLs have been re-built and sent to S3 you can set the run groups again, this time to `"RunDLL"` and the
   monitor will now move from your local environment to the new style orchestrator.
1. Verify that the new style orchestrator invokes your monitor, reporting is ok, and move your ticket to Done.
