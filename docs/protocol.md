# Orchestrator/Monitor protocol

## Introduction

To separate concerns and allow monitors to be written in any language, two design decisions were made:

1. Monitors are separate, stand-alone executables;
2. The orchestrator has fine-grained control of the monitoring code so that the monitoring code can focus
   on the actual scenarios.

To this end, it is necessary that the orchestrator can control a monitor executable in a language-independent
manner. We have chosen to solve this by passing messages on stdin/stdout, which theoretically means that even
shell scripts should be able to implement monitors.

## Message Syntax

We want messages to be humanly-readable. This is not a high-volume application, so we can skip efficiencies. The
most important thing is that, whatever the language the monitor is written in, it can reliably read messages. A simple
and portable way is to prefix messages with a length:

    <5 length bytes><space><message bytes....>

A monitor can read 5 bytes or scan for the space, parse the length, and then do a fixed-buffer read for the rest of the
message. This ensures that we can send line termination characters and other "special characters".

A message is normally a keyword and optional data. If the data is simple, it is sent as-is. If it is more complex, it
is sent as a JSON string. An example message:

    00006 Hello\n

Note that the line feed is not necessary (and whitespace is typically trimmed), so this message should be equivalent for
all practical purposes:

    00005 Hello

Note that message keywords are case-sensitive and typically start with an uppercase letter to make them easier to read
for humans. The time that we needed to talk SMTP to EBCDIC computers is long over so no need to shout in all-caps :)

In the documentation below, we leave out the field length and leading space when describing messages; `<thing>` means
that thing is a required element of a message, and `[thing]` that it is optional. The ellipsis will mean that something can
be repeated.

## Handshake

When the monitor starts up, it signals its readiness to participate in the protocol by a single message

    Started <major>.<minor>

where the `major` and `minor` components stand for the monitor's understanding of the protocol. This follows standard
semantic versioning rules: a major change is breaking and a minor change is compatible with earlier versions. The
orchestration code will then respond with its understanding of the world:

    Version <major>.<minor>

and if everything checks out w.r.t. compatibility, neither side will "hang up" (it is entirely acceptable for a monitor
to just exit with an error message if it decides that it cannot handle the version required). The monitor will signal
its happiness with the protocol compatibility through a simple:

    Ready

The final step in the handshake is to pass configuration data to the monitor, which can be anything that the monitor needs
to do its work (for example, a Github monitor would need to know what Github repository to operate on, what credentials to
use, and so on). The orchestrator will send this configuration data upon receiving the ready:

    Config <json_data>

And the monitor will parse it. Note that at this point, the protocol only requires a syntactic validation ("can I parse it
and store it for later use?") and not necessarily a full semantic validation("is all the data there and in the expected form?"). When
that is done, the protocol handshake is ended by the monitor by:

    Configured

## Monitor Logging

The scheduler will be relatively robust against all sort of noise being received - libraries may want to print to stdout, but
these messages are unlikely to follow the format above. This "noise" is captured and forwarded as logging data. However, if the
monitor wants to make it explicit that it is logging, and use logging levels, it can do so with the logging messages:

    Log Debug <message>

    Log Info <message>

    Log Warning <message>

    Log Error <message>

Where the run-time environment allows it, messages will then be logged with the same or equivalent log levels and tagged with
metadata like what monitor emitted the message.

## Running steps

When the monitor is ready, the orchestrator will run the individual steps. This is done so we can implement any smarts around
this process once, the monitor just needs to implement a step function and nothing else. At this point, the monitor should
wait for either:

    Exit

signaling that all is done and the process is expected to shut down, or

    Run step <step name>

to run a step function. The step function can either be self-timed (often, a step needs to do some setup which may be more expensive
than the actual check, so in that case the step function will execute the setup and then time the code that runs the actual check), which
should return:

    Step Time <time-in-seconds>

(where time can be a float), or if it is not self-timed:

    Step OK

The orchestrator will then take care of the timing. In both cases, if an error occurs that prevents the step from generating a timing,
it should be signalled as follows:

    Step Error <error message>

In the latter case, it is up to the orchestrator to decide whether to run any more steps.

Note that on Exit, the monitor may elect to do some cleanup.
