# Orchestrator

This repository contains the Metrist orchestrator, which includes two main functions:

* Orchestration of monitor runs, and,
* Forwarding of in-process monitoring data it receives.

The orchestrator is written in Elixir and distributed both as a standalone executable and a container.

## Installation

See our [installation documentation](INSTALL.md) for instructions.

## Orchestration

Based on monitor configurations maintained on the Metrist backend, the orchestrator will schedule runs
of checks for certain monitors. It is configured with an instance ID that allows the backend to keep
track of when something was last run and one or more "run groups" that allow the backend to decide what
monitors and checks are configured to run on that particular instance of the orchestrator.

When a monitor is up for its run, it is downloaded from a Metrist-managed AWS S3 bucket so that the latest version of
a monitor is always executed; it is then started and the monitor is expected to participate in a simple
[protocol](docs/protocol.md) to exchange configuration data and have the orchestrator drive the monitoring code
through the configured scenario. For every step, a timing is obtained and the orchestrator sends that back to
the Metrist backend.

## In-process forwarding

The Metrist orchestrator comes with a handler for in-process monitoring. For every Metrist In-Process Agent (IPA) message it receives,
it will try to match the messages against its configuration to see whether it needs to be forwarded to the Metrist backend.

IPA messages consist of four fields: the HTTP method, the URL, the path, and the time it took for the HTTP transaction to
complete. A configuration file can be specified by pointing the environment variable `METRIST_CMA_CONFIG` to a YAML file with
contents similar to this snippet:

```yaml
patterns:
  braintree.Transaction:
    method: any
    host: api.*.braintreegateway.com
    url: /transaction$
```

You can specify as many patterns as you like. The key is in the format "monitor-name.check-name", which you can both obtain
from our web UI. `method` and `url` can both be left out or for clarity specified as `"any"` in which case everything matches. All
three fields are normal regular expressions that are matched against the corresponding fields in the IPA message. If it matches,
the measured value will be sent to the Metrist back-end.

## Configuration

The orchestrator is configured through environment variables:

* `METRIST_INSTANCE_ID` - this is the instance id used for reporting. It can be any logical name, but should be unique and consistent between
  runs as the backend will use this to supply the instance with the timings of last monitoring runs.
* `METRIST_RUN_GROUPS` - one or more "run groups" this monitor will schedule. When more than one, a comma-separated list. This can be
  used to have several instances of monitors run some same set of monitors.
* `METRIST_CLEANUP_ENABLED` - if set, a flag that determines whether to run cleanup actions. Monitors can have a "Cleanup" action
  that usually is there to remove artefacts of previous runs which these runs could not remove themselves (because of a crash or
  a provider outage, for example). Because these operations can be expensive, it is best to only schedule them on a subset of instances.
* `METRIST_SECRETS_SOURCE` - when monitors need secrets like API keys, a pointer to the secrets source. Currently only "aws" is
  supported (and the default), which will try to retrieve secrets from AWS Secrets Manager.
* `METRIST_CMA_CONFIG` - the agent configuration file, currently only used for in-process forwarding patterns as described above.
* `METRIST_LOGGING_LEVEL` - the level to log at; usually the "Info" default is fine but somethings "Debug" makes sense, and "Error"
  can be used to make the process less talkative. "Notice", "Warning", "Critical", "Alert" and "Emergency" are also accepted options
  but will usually not make too much of a difference and might not be supported by all monitors that also interpret this variable.
* `METRIST_IPA_LOOPBACK_ONLY` - whether to open the UDP socket for in-process data only on the loopback/localhost address. This can be
  used to restrict this sort of traffic to only the local machine. Off by default which means that the "wildcard" address is bound,
  making the UDP socket accessible to all machines that can route to the instance.

## License

This software is licensed to the public under the [Apache License, Version 2.0](LICENSE.txt) - details are
in that file.
