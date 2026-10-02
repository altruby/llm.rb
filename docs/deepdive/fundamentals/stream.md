
## Stream

### Introduction

#### Overview

Streaming delivers model output as it is generated, token by
token, instead of waiting for the full response. The user sees
text appear in real time, and the application can act on partial
results as they arrive.

#### How it works

The stream target can be any object that responds to `#<<`. Each
time the provider emits a token, the runtime calls `target <<
chunk` with the raw content. The tokens arrive in order as the
model generates them, so the output appears character by character
instead of all at once. When the response is complete, the stream
closes and control returns to the caller.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "hello world"
```

#### Why would I use it?

Streaming lets users see output sooner and cancel mid-response if
the model goes off course. It also lets you add progress indicators and
partial result processing, things that are not possible with a
single blocking response.

#### Notes

The IO-like form is equivalent to
[`LLM::Stream#on_content`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_content)
and does not include the other hooks. It covers content output
(piping to stdout or a log file) without the overhead of a full
subclass. A
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
subclass gives you visibility into tool calls, compaction events,
and reasoning content.

### Callbacks

#### Overview

A stream subclass provides structured hooks into content, tool
calls, compaction, and other runtime events. Each hook fires at
a specific point in the request lifecycle. This gives you
fine-grained visibility into what the runtime is doing as it
happens, from the first token to the final tool return.

#### How it works

When you want to react to specific runtime events, override the
hooks on a
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
subclass.
[`LLM::Stream#on_content`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_content)
receives tokens as they arrive.
[`LLM::Stream#on_tool_call`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_tool_call)
fires when the model requests a tool.
[`LLM::Stream#on_tool_return`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_tool_return)
fires when the tool completes.
[`LLM::Stream#on_step`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_step-instance_method)
fires when a request completes, which is the boundary between one
request and the next: the response is in the conversation, and a
turn that asked for tools runs them after this while a turn that is
finished ends here. That boundary is where a conversation is whole,
and the runtime's
[`LLM::Step`](https://r.uby.dev/api-docs/llm.rb/LLM/Step.html) is
written against it - it is prepended onto a stream, and saves the
conversation through the record the context is bound to, so a turn
that is interrupted can be continued from its last completed request
rather than started over.
[`LLM::Stream#on_retry`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_retry)
fires each time a failed request is retried. Compaction hooks
let you show progress or log what was trimmed. Skill hooks bracket a
skill's subagent execution:
[`LLM::Stream#on_skill_call`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_skill_call)
fires before a skill's subagent runs, and
[`LLM::Stream#on_skill_return`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_skill_return)
fires after it finishes.

```ruby
class MyStream < LLM::Stream
  # Visible assistant output.
  def on_content(content)
    print content
  end

  # Reasoning output streamed separately from visible content.
  def on_reasoning_content(content)
    warn content
  end

  # A streamed tool call has been fully parsed.
  def on_tool_call(tool)
  end

  # Queued streamed tool work has returned.
  def on_tool_return(tool, result)
  end

  # A request has completed: the response is in the conversation, and
  # any tools it asked for run after this.
  def on_step(ctx, res)
  end

  # Before a transformer rewrites an outgoing message.
  def on_transform(transformer)
  end

  # Aftter a transformer rewrites an outgoing message.
  def on_transform_finish(transformer)
  end

  # Before a compactor trims the conversation.
  def on_compaction(compactor)
  end

  # After a compactor trims the conversation.
  def on_compaction_finish(compactor)
  end

  # Before a skill's subagent runs.
  def on_skill_call(skill)
  end

  # After a skill's subagent runs.
  def on_skill_return(agent, skill, result)
  end

  # A request was rate limited or timed out and will be retried.
  def on_retry(error, attempt)
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: MyStream.new)
agent.talk "Explain Ruby fibers."
```

#### Why would I use it?

A stream subclass gives you visibility into more than just content chunks. React to tool
calls as they happen, show compaction progress, or integrate with
an existing observability stack.

### Streamed tool execution

#### Overview

A tool call is a round trip. By default the runtime makes it after the
response has finished streaming, so the model sits idle for the length
of the tool. A stream can start the tool the moment its call is parsed
instead, and hand the result to the turn when it is asked for.

#### How it works

Start the tool from
[`LLM::Stream#on_tool_call`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_tool_call)
and enqueue its task on
[`LLM::Stream#queue`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#queue-instance_method).
[`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait-instance_method)
drains that queue in preference to the pending functions, so a tool that
was started early is waited for, not run twice:

```ruby
class FastStream < LLM::Stream
  def on_tool_call(tool)
    queue << tool.task(:thread).tap(&:spawn)
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: FastStream.new)
agent.talk "Read every file in lib/ and summarise them."
```

[`LLM::Stream::Queue`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream/Queue.html)
takes either a running task or an immediate
[`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html),
and
[`LLM::Stream#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#wait-instance_method)
resolves whatever it holds and returns the returns. The task type is
remembered, so no strategy is passed at wait time.

#### Why would I use it?

A turn that calls several tools spends most of its wall-clock time
waiting. Starting each tool as its call arrives overlaps that wait with
the rest of the stream, so a turn that reads ten files costs roughly one
file's latency rather than ten.

#### Notes

The queue is only consulted when it is non-empty. A turn that enqueues
nothing behaves exactly as before, and a turn that enqueues from
`on_tool_call` still runs any *other* pending function through the
strategy given to
[`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait-instance_method).
A cancel reaches the queue
([`LLM::Stream::Queue#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream/Queue.html#interrupt!-instance_method)),
so tools started this way are interrupted with the rest of the turn.
