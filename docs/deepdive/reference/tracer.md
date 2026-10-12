
## Tracer

### Introduction

#### Overview

Tracers let you observe what the runtime is doing. They hook into
requests, tool calls, compactions, and other events. Debug a
misbehaving agent, monitor request latency, or export spans to
an observability backend. A provider-wide tracer intercepts every
request through that provider. An agent-local tracer only covers
requests made by that agent.

#### How it works

When you want to observe runtime events, subclass
[`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
and implement the hooks you need, or use one of the built-in
tracers. The built-in tracers include
[`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html)
(writes structured JSON to stdout or a file),
[`LLM::Tracer::PrettyLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html)
(writes human-readable single-line logs to stderr), and
[`LLM::Tracer::Telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Telemetry.html)
(exports spans via OTLP for OpenTelemetry). Attach a tracer to a
provider or an agent:

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
llm.tracer = LLM::Tracer.pretty_logger(llm)
agent = LLM::Agent.new(llm)
agent.talk "Hello"
```

#### Why would I use it?

Tracers give you visibility into what the runtime is doing. Debug
a misbehaving agent by tracing every request it makes. Monitor
request latency and token usage across providers. Export spans to
OpenTelemetry for integration with existing observability pipelines.
[`LLM::Tracer::PrettyLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html)
is the best choice during development for compact, human-readable
output.
[`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html)
provides structured JSON, and
[`LLM::Tracer::Telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Telemetry.html)
exports spans to OpenTelemetry for production observability.

#### Notes

The tracer is extensible. You can implement custom hooks for any
runtime event. The scope can be an individual agent or every
request a provider makes. Three built-in tracers are available:
[`LLM::Tracer::PrettyLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html)
(human-readable),
[`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html)
(structured JSON), and
[`LLM::Tracer::Telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Telemetry.html)
(OpenTelemetry).

For a shorter way to build the built-in tracers, use the
[`LLM::Tracer.logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#logger-class_method),
[`LLM::Tracer.pretty_logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#pretty_logger-class_method),
and
[`LLM::Tracer.telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#telemetry-class_method)
convenience methods. Each takes a provider and forwards its options to
the matching tracer, so `LLM::Tracer.pretty_logger(llm, io: $stdout)`
forwards `io:` to the pretty logger.

### Provider

#### Overview

A provider-wide tracer intercepts every request made through that
provider. All agents sharing the same provider share the same
tracer. Use this to trace at the infrastructure level without
configuring each agent individually.

#### How it works

When you want every request through a provider to be traced, set
the tracer on the provider directly. Every request made through
that provider, regardless of which agent initiates it, flows
through the same tracer hooks. The provider holds a reference to the
tracer and passes it to every new context it creates. This ensures
consistent observability without configuring each agent individually.

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
llm.tracer = LLM::Tracer.logger(llm, io: $stdout)
```

#### Why would I use it?

A provider-wide tracer captures every request at the infrastructure level.
All agents sharing the same provider share the same tracer.

#### Notes

The tracer can also write to a file with the `path:` option to
[`LLM::Tracer::Logger.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html#initialize-instance_method).

### Agent

#### Overview

An agent-local tracer only covers requests made by that agent.
Attach it via the `tracer:` keyword argument to
[`LLM::Agent.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#initialize-instance_method)
and it follows that agent wherever it goes. Different agents can
have different tracers.

#### How it works

When you want a tracer for a specific agent, pass it to the agent
on creation. Only requests made by
that agent flow through the tracer, leaving other agents on the
same provider unaffected.

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tracer: LLM::Tracer.logger(llm, io: $stdout))
```

#### Why would I use it?

Agent-local tracers let each agent log differently.
One agent might log to stdout, another to a file, a third to
OpenTelemetry.

#### Notes

The tracer can also write to a file with the `path:` option to
[`LLM::Tracer::Logger.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html#initialize-instance_method).

### Multi

#### Overview

[`LLM::Tracer::Multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Multi.html)
fans every tracing callback out to a set of tracers, so one request can
be logged to a file and exported to OpenTelemetry at the same time
rather than choosing between them.

#### How it works

Pass the tracers to `new`. A `Multi` has no provider of its own, so it
is not built from a factory method the way the built-in tracers are:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
llm.tracer = LLM::Tracer::Multi.new(
  LLM::Tracer.pretty_logger(llm),
  LLM::Tracer.telemetry(llm)
)
agent = LLM::Agent.new(llm)
agent.talk "Hello"
```

`on_request_start` and `on_tool_start` return an array with one span per
tracer, in the same order as
[`LLM::Tracer::Multi#tracers`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Multi.html#tracers-instance_method).
Pass that array back as `span:` to the matching finish, error, or
interrupt callback and each tracer is handed the span it returned. A
tracer that raises is reported the way
[`LLM::Tracer::Rescue`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Rescue.html)
reports any other, and the remaining tracers still run.

#### Why would I use it?

It is how you keep a human-readable log and a machine-readable trace from
diverging: one tracer sees the events in development, another sees them
in production, and neither has to know about the other.

#### Notes

A `Multi` holds no provider, so its inherited `on_exit`, `spans`, and
`flush!` are its own rather than any child's: the callbacks are fanned
out, but a span list or a flush is asked of the tracer that owns it.

### Hooks

#### Overview

[`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
exposes one method per event in a request's lifecycle. A subclass
implements the events it cares about and routes them anywhere: a
logger, a metrics counter, or a database table.

#### How it works

Three hooks cover a provider request. `on_request_start` fires before
the request is sent and returns the span that `on_request_finish` and
`on_request_error` receive. Every request carries a `request_id`, a
UUIDv7 minted when the request begins and passed to all three hooks
for that request, so a tracer can correlate its events even when a
turn makes several requests.

Three more hooks cover a local tool call. `on_tool_start` fires before
the tool runs and returns the span that `on_tool_finish` and
`on_tool_error` receive.

An interrupt is neither a finish nor an error, and it is reported to a
hook of its own. `on_interrupt` is called with a `scope:` of `:request`,
`:tool`, or `:agent` before the caller is given the exception, so a
tracer that records what happened to a turn records it while the work is
still in flight. The hook receives the span that `on_request_start`
returned and its `request_id`; a tool pass carries neither, because a
tool's span belongs to the call, and an `:agent` pass is one that landed
between a turn's requests, where there was nothing more precise to
interrupt. A cancel reaches every tool that is running, so the tool phase
is announced once rather than once per tool.

A tool call that was interrupted is closed through `on_tool_interrupt`
as well, which is handed the exception the caller is given and the span
`on_tool_start` returned. That span is the only thing that can name a
call which never returned a result, so a tracer can pair a start with an
end rather than leaving the span open.

A tracer's own lifetime is bracketed as well. `on_exit` fires once,
when the last scope that is open for that tracer ends. That scope can
belong to a different thread than the one that opened the first: a tool
runs on a thread of its own and scopes the turn's tracer while it does.
`on_exit` is called after the scoped lookup has been restored, so a
tracer that asks its provider for the current tracer from inside it
sees the tracer the next request will see. A tracer can be scoped again
afterwards, so it has to remain usable after `on_exit`, and `on_exit`
may be called more than once over its life.

A turn is additionally bracketed with `start_trace` and `stop_trace`.
The runtime calls them around every agent turn with a `trace_group_id`,
and a tracer that supports it (such as
[`LLM::Tracer::Telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Telemetry.html))
uses that id to give every span of the turn the same trace id:

```ruby
class MyTracer < LLM::Tracer::Null
  def on_request_start(operation:, model: nil, **)
    warn "start #{operation} #{model}"
  end

  def on_request_finish(operation:, res:, **)
    warn "finish #{operation}"
  end

  def on_tool_start(id:, name:, arguments:, model:, **)
    warn "tool #{name}"
  end

  def on_tool_interrupt(ex:, span:, **)
    warn "tool interrupted: #{ex.class}"
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
llm.tracer = MyTracer.new(llm)
agent = LLM::Agent.new(llm)
agent.talk "Hello"
```

#### Why would I use it?

The built-in tracers cover logging and OpenTelemetry. A hook lets you
send the same events somewhere else, and because the built-in tracers
accept the keywords they do not use, existing tracer code keeps working
as hooks gain parameters.

#### Notes

The superclass raises `NotImplementedError` for every hook the runtime
calls, so subclassing
[`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
means answering all of them: the six request and tool hooks above,
`on_tool_interrupt`, `on_interrupt`, and `on_exit`.
[`LLM::Tracer::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Null.html)
answers them all with a no-op, which is the shorter route when you want
only a few, and what the example above takes. `start_trace` and
`stop_trace` are the exception: their base implementations are no-ops
rather than raises, because a tracer that keeps no trace has nothing to
open or close.

A hook that raises does not take the turn with it.
[`LLM::Tracer::Rescue`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Rescue.html)
is prepended onto every subclass of `LLM::Tracer`, so the raise is
reported on standard error and the turn carries on. `LLM::Interrupt` is
re-raised, since a cancel is not a tracer's to swallow.

Accept `**` to absorb keywords you do not read, as the built-in tracers
do, so a hook that gains a parameter does not break your subclass.

### PrettyLogger

#### Overview

[`LLM::Tracer::PrettyLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html)
writes human-readable single-line logs to stderr. Unlike
[`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html)
(which emits structured JSON), the pretty logger is designed for
interactive development sessions where you want to see request and
tool-call activity at a glance.

#### How it works

Each request and tool call produces a single line on stderr with
the model, duration, and a summary of the activity. The logger
accepts an `io:` option to redirect output.

##### Provider-wide

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
llm.tracer = LLM::Tracer.pretty_logger(llm)
```

##### Agent-local

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tracer: LLM::Tracer.pretty_logger(llm))
```

##### Custom output

```ruby
tracer = LLM::Tracer.pretty_logger(llm, io: $stdout)
tracer = LLM::Tracer.pretty_logger(llm, path: "trace.log")
```

#### Why would I use it?

The pretty logger is the best choice for development. The output is
compact enough to follow in real time while still showing the model
name, duration, and tool calls. Switch to
[`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html)
when you need structured JSON for programmatic analysis, or to
[`LLM::Tracer::Telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Telemetry.html)
when you need OpenTelemetry exports.

#### Notes

The pretty logger writes to `$stderr` by default. Set `io:` to
redirect output. All three built-in tracers share the same interface,
so switching between them requires changing only the class name.
