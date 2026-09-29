
## Tools

### Introduction

#### Overview

A tool is how a model reaches outside its own head. Without tools,
the model can only produce text. With a tool, it can run a shell
command, query a database, or fetch a web page. The model decides
when a tool fits the request; the runtime calls it and sends the
result back.

A tool is a Ruby class with a name, a description, and a
[`LLM::Tool#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#call)
method. The name tells the model what the tool is called. The
description tells the model when to use it. The
[`LLM::Tool#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#call)
method receives the arguments and returns the result. That is the entire
contract: name, description, parameters, and a method that runs.

#### How it works

A tool is a subclass of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
with a name, description, and optional typed parameters. The model sees the name and
description and decides whether to call it. When it does, the
runtime serializes the arguments and passes them to
[`LLM::Tool#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#call).

Tools that spawn subprocesses can include
[`LLM::Tool::Utils`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html)
to get shared
[`wait(command:, timeout:)`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html#wait-instance_method)
and `now` help. The built-in `Exec`, `Git`, `Rg`, `Mkdir`, and `Ruby`
tools use it to kill a command that exceeds its `timeout`.

If
[`LLM::Tool#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#call)
raises, the runtime rescues it and returns a structured
error to the model instead. The conversation stays valid. You can
also handle errors yourself inside
[`LLM::Tool#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#call)
by rescuing and returning a domain-specific error hash.

```ruby
require "llm/tools/utils"

class Exec < LLM::Tool
  include Utils

  name "exec"
  description "run a command without a shell"
  parameter :arguments, Array[String], "a command and its arguments"
  required %i[arguments]
  defaults timeout: 60, max_bytes: :max_bytes

  def self.max_bytes(bytes = nil)
    bytes ? (@max_bytes = bytes) : (@max_bytes || 75_000)
  end

  def call(arguments: [], timeout: 60, max_bytes: self.class.max_bytes)
    name = arguments[0]
    command = spawn(name:, arguments: arguments[1..], max_bytes:)
    wait(command:, timeout:)
    {ok: command.success?, stdout: command.stdout, stderr: command.stderr}
  rescue LLM::Interrupt
    command.kill! if command&.running?
    raise
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: [Exec], stream: $stdout)
agent.talk "What files are in the current working directory?"
```

#### Why would I use it?

Tools are how the model interacts with the outside world, and the
model is the orchestrator. When you give an agent a handful of
tools and ask it to do something open-ended, the model reads each
tool's name and description, chooses which to call, and picks the
arguments. The runtime just executes. The model can chain tools
into a multi-step workflow, retry after a failure, or fan several
calls out in parallel and synthesize the results.

That orchestration is the killer feature. One tool lets the model
reach outside itself; several tools let it plan and execute a
whole job. A single "research the competitors and compare their
pricing" turn can fan out to a web search, a database query, and an
API call at once, then return a synthesized answer. See
[Fan-out with tools](#fan-out-with-tools) below for the pattern.

#### Notes

Confirmation gates tools behind explicit approval. List tool names
in
[`LLM::Agent#confirm`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#confirm)
to block execution until you override
[`LLM::Agent#on_tool_confirmation`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#on_tool_confirmation).
Confirmation also accepts a Symbol that resolves to an instance
method, letting the confirmed set change per-instance based on
runtime conditions.

Tool properties can be defined with individual method calls (as shown
in the How it works section) or with
[`LLM::Tool.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#set-class_method)
(see the Set subsection). Both approaches work the same way.

### Confirmation

#### Overview

Tools that perform destructive actions can be gated behind explicit
approval. List their names in
[`LLM::Agent#confirm`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#confirm)
to block execution
until you override
[`LLM::Agent#on_tool_confirmation`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#on_tool_confirmation).
The default handler cancels
the tool. Override it per-agent to prompt the user, log the decision,
or auto-approve certain tools.

#### How it works

When you want to override the default approval flow for a gated
tool, override
[`LLM::Agent#on_tool_confirmation`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#on_tool_confirmation)
on the subclass. The method receives the pending function and the
execution strategy. Call
[`LLM::Function#task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#task)
to execute the tool or
[`LLM::Function#cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#cancel)
to block it. The default handler cancels the call.

```ruby
class AdminAgent < LLM::Agent
  set confirm: %w[delete destroy shutdown]

  def on_tool_confirmation(fn, strategy)
    print "Run #{fn.name} with #{fn.arguments}? [y/N] "
    $stdin.gets&.match?(/\Ay\z/i) ? fn.task(strategy).wait : fn.cancel
  end
end
```

#### Why would I use it?

Confirmation prevents the model from running dangerous tools
without user oversight. You decide the approval flow: a terminal
prompt, a web socket, a background job queue.

#### Notes

Confirmation names can be a static array of tool names or a Symbol
that resolves to an instance method. The Symbol form lets the
confirmed set change per-instance based on runtime conditions.

### Errors

#### Overview

A tool that raises does not crash the conversation. The runtime
catches the exception, wraps it into a structured error, and
returns it to the model. The model can read the error, decide what
went wrong, and try something else. The tool loop stays alive no
matter what.

#### How it works

If
[`LLM::Tool#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#call)
raises, the runtime returns `{error: true, type: "RuntimeError",
message: "boom"}` to the model. A tool can also check for a known
failure and return its own error shape, which gives the model
more context than a generic error. The `exec` tool, for example,
reports a missing command through `command.not_found?` rather than
letting the spawn fail.

```ruby
require "llm/tools/utils"

class SafeExec < LLM::Tool
  include Utils

  name "safe-exec"
  description "run a command and report a missing one"
  parameter :arguments, Array[String], "a command and its arguments"
  required %i[arguments]
  defaults timeout: 60, max_bytes: :max_bytes

  def self.max_bytes(bytes = nil)
    bytes ? (@max_bytes = bytes) : (@max_bytes || 75_000)
  end

  def call(arguments: [], timeout: 60, max_bytes: self.class.max_bytes)
    name = arguments[0]
    command = spawn(name:, arguments: arguments[1..], max_bytes:)
    wait(command:, timeout:)
    if command.not_found?
      {ok: false, error: "command '#{name}' was not found on this system"}
    else
      {ok: command.success?, stdout: command.stdout, stderr: command.stderr}
    end
  end
end
```

#### Why would I use it?

Custom error handling gives the model domain-specific detail that
helps it recover. Instead of a generic "RuntimeError: boom", the
model sees `{ok: false, error: "command 'ls' was not found on this
system"}` and knows to correct the command name and try again.

#### Notes

The principle is the same either way: return something. A tool call
must complete with a tool response. If you do not return a value and
you do not raise, the runtime has nothing to send back and the
conversation is stuck.

### Set

#### Overview

[`LLM::Tool.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#set-class_method)
is an alternative way to define tool properties using a Hash. It
works the same way as individual method calls and accepts the same
keys: `name`, `description`, `parameters`, `required`, and
`defaults`.

#### How it works

When you want to define tool properties at once, call
[`LLM::Tool.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#set-class_method)
with a Hash. The keys match the individual method names. The
`parameters` key accepts the same Array of tuples that the
individual `parameter` method does.

```ruby
require "llm/tools/utils"

class Exec < LLM::Tool
  include Utils

  set name: "exec",
      description: "run a command without a shell",
      parameters: [
        [:arguments, Array[String], "a command and its arguments", {required: true}],
        [:timeout, Integer, "timeout in seconds", {default: 60}],
        [:max_bytes, Integer, "max bytes to emit", {default: 75_000}]
      ]

  def self.max_bytes(bytes = nil)
    bytes ? (@max_bytes = bytes) : (@max_bytes || 75_000)
  end

  def call(arguments: [], timeout: 60, max_bytes: self.class.max_bytes)
    name = arguments[0]
    command = spawn(name:, arguments: arguments[1..], max_bytes:)
    wait(command:, timeout:)
    {ok: command.success?, stdout: command.stdout, stderr: command.stderr}
  end
end
```

#### Why would I use it?

`set` is useful when you want to keep related properties together.
Instead of spreading `name`, `description`, `parameters`, and
`required` across multiple lines, you can group them in a single
Hash that reads like a configuration block.

#### Notes

Unknown keys raise `KeyError`, so typos are caught at class load
time rather than at runtime.

For a parameter shape that the typed `parameter` form does not cover,
[`LLM::Tool.params`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#params-class_method)
yields the schema object directly, so the same value methods a schema
uses are available:

```ruby
class Search < LLM::Tool
  name "search"

  params do |schema|
    schema.object(
      query: schema.string.required,
      limit: schema.integer.default(10)
    )
  end

  def call(query:, limit: 10)
    results(query, limit:)
  end
end
```

### Fan-out with tools

#### Overview

The fastest way to see the model's orchestration in action is to
give it several independent tools and let it run them in parallel.
This is where tools and
[concurrency](concurrency.md) meet: the model decides it needs
multiple answers, issues several tool calls, and the runtime
executes them concurrently before feeding every result back for
synthesis.

#### How it works

Attach independent tools to an agent and set a concurrency strategy
that matches the workload. For IO-bound tools like HTTP fetches,
`:async` or `:thread` give you parallelism without much overhead.
For process isolation or CPU-bound work, reach for `:fork` or
`:ractor`. The agent runs the tool loop, so it keeps calling,
collecting, and synthesizing until it has the answer. The model
reads the tool descriptions, decides which are independent, and
issues the calls. The runtime fans them out across the chosen
strategy, waits, and returns the combined results as context so the
model can synthesize a single answer:

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
tools = [FetchNews, FetchStocks, FetchFeeds]
agent = LLM::Agent.new(llm, tools:, concurrency: :fork)
agent.talk "Run the tools in parallel and summarize the results"
```

#### Why would I use it?

Parallel tool execution turns N round trips into one. A research,
monitoring, or automation agent that would otherwise call one tool,
wait, call the next, now gathers everything at once. The result
arrives faster and the model still gets the full picture before it
writes. The strategy is a single option, so you tune the trade-off
between speed (IO), isolation (fork), and CPU parallelism (ractor)
without touching your tool code.

#### Notes

The six strategies are documented in
[concurrency](concurrency.md). Whichever you choose, the tool
loop, confirmation, and error handling behave identically. A single
failing tool returns a structured error to the model, which can
decide to retry or continue with the results it has.

### Platform-native tools

#### Overview

Some capabilities live inside the provider rather than on your
machine. Web search, code execution, file search, and computer use are
examples: the provider runs them on its own infrastructure, and the
model can call them directly. The runtime represents these with
[`LLM::ServerTool`](https://r.uby.dev/api-docs/llm.rb/LLM/ServerTool.html).
A server tool is not an
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
subclass, so it never appears in `LLM::Tool.subclasses`.

#### How it works

Build a server tool from a provider with
[`LLM::Provider#server_tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#server_tool-instance_method),
or read a ready-made one from the provider's catalog with
[`LLM::Provider#server_tools`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#server_tools-instance_method).
Pass server tools in the same `tools:` list as local tools:

```ruby
require "llm"

llm = LLM.google(key: ENV["KEY"])
ctx = LLM::Context.new(llm, tools: [llm.server_tool(:google_search)])
ctx.talk "Summarize today's news"
```

Each provider defines its own catalog. OpenAI offers `web_search`,
`file_search`, `image_generation`, `code_interpreter`, and
`computer_use`; Google offers `google_search`, `code_execution`, and
`url_context`; Anthropic offers `bash`, `web_search`, and
`text_editor`.

#### Why would I use it?

A server tool saves you from building and hosting the capability
yourself. Search, code execution, and file search run on the
provider's side, so the model can call them without a local tool
loop, a service of your own, or extra credentials.

#### Notes

OpenAI, Google, and Anthropic also expose a `web_search(query:)`
method that performs a search in one call and returns the results. A
server tool accepts whatever options the provider documents, for
example `llm.server_tool(:web_search, max_uses: 5)` on Anthropic.

### Built-in tools

#### Overview

llm.rb ships with thirteen ready-made tools that cover filesystem,
search, and shell operations. Load them all with
`require "llm/tools"`. Each tool is documented in the
[built-in tools catalog](builtin_tools.md).

#### How it works

When you want to attach the built-in tools to an agent, require
the catalog and pass the full set of subclasses as the `tools:`
option.

```ruby
require "llm"
require "llm/tools"

llm   = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: LLM::Tool.subclasses)
```

#### Why would I use it?

The built-in tools cover the operations a coding or system agent
needs most. See the
[built-in tools catalog](builtin_tools.md) for the full reference.

#### Notes

The tools that spawn subprocesses use the optional `test-cmd.rb`
gem for process management and interrupt handling.

`LLM::Tool.subclasses` lists the direct subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html), so a
tool defined under an intermediate base class is not in the list.
[`LLM::Tool.registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#registry-class_method)
lists every tool that has a name, wherever it sits in the hierarchy.

### Interrupts

#### Overview

A tool call can be cut short, either because the user cancelled the
turn or because the runtime stopped the request. A tool that holds a
resource can release it by overriding
[`LLM::Tool#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_interrupt-instance_method),
which the runtime calls when an in-flight call is interrupted.

#### How it works

The runtime calls
[`LLM::Tool#on_cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_cancel-instance_method),
whose default implementation calls `on_interrupt`. Override
`on_interrupt` for cleanup that applies to both cases:

```ruby
class LongJob < LLM::Tool
  name "long_job"

  def call(job_id:)
    @job = start_job(job_id)
    wait_for(@job)
  end

  def on_interrupt
    @job&.stop
  end
end
```

#### Why would I use it?

A tool that started a subprocess, opened a connection, or wrote a
partial file has something to undo when the call is cut short.
`on_interrupt` is where that cleanup belongs, so the work does not keep
running after the turn is over.

#### Notes

The hooks are cooperative: the runtime calls them and the tool decides
what happens. Override `on_cancel` instead of `on_interrupt` when a
cancellation needs to be told apart from an interrupt, and call `super`
if both should clean up.
