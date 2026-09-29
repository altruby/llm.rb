
## A2A

### Introduction

#### Overview

The Agent-to-Agent (A2A) protocol lets agents communicate directly
over a network. Unlike MCP, which connects an agent to external
tools, A2A connects agents to other agents. A remote agent advertises
its skills through a card. The calling agent loads those skills as
local tools and calls them the same way it calls any other tool.
One agent can research, another can code, a third can review.

#### How it works

The REST transport communicates over standard HTTP and JSON. Both
transports expose the remote agent's skills as local
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
subclasses.

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
a2a   = LLM::A2A.rest(url: "https://agent.example.com")
agent = LLM::Agent.new(llm, tools: a2a.skills)
agent.talk "What's happening, fellow agent?"
```

#### Why would I use it?

A2A lets you compose autonomous agents that delegate and collaborate.
One agent researches a topic. Another writes code. A third reviews
the result. Each agent runs independently and communicates over
the network.

#### Notes

An agent's capabilities are advertised through a card. The
[`LLM::A2A::Card#interfaces`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A/Card.html#interfaces)
method lists which transports a remote agent supports.

##### Persistent connections

A persistent connection reuses the same HTTP connection across
requests to the same A2A agent. Both REST and JSON-RPC transports
accept the `persistent: true` option. Persistent connections matter
when an agent makes many requests to the same remote agent in a
short window, since reusing the connection avoids the handshake and
teardown overhead of a fresh TCP connection per request. The option
defaults to `false`; for a single request or an infrequent pattern,
the overhead is negligible. When you want to avoid reopening a TCP
connection for every request, pass `persistent: true` to the
transport constructor. This uses
[`Net::HTTP::Persistent`](https://github.com/drbrain/net-http-persistent)
under the hood:

```ruby
a2a = LLM::A2A.rest(url: "https://agent.example.com", persistent: true)
a2a = LLM::A2A.jsonrpc(url: "https://agent.example.com", persistent: true)
```

### JSON-RPC

#### Overview

JSON-RPC is an alternative transport for A2A agents. It uses a
more structured protocol than REST, with request and response
objects that follow the JSON-RPC 2.0 spec. Some agents advertise
only JSON-RPC, others advertise both. The
[`LLM::A2A::Card#interfaces`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A/Card.html#interfaces)
method lists which transports a remote agent supports.

#### How it works

When you want to connect to a remote A2A agent using JSON-RPC,
provide a URL and optional headers. The agent's skill list is
fetched and translated into
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) subclasses the model can call.

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
a2a   = LLM::A2A.jsonrpc(url: "https://agent.example.com")
agent = LLM::Agent.new(llm, tools: a2a.skills)
agent.talk "What's happening, fellow agent?"
```

#### Why would I use it?

JSON-RPC provides typed request and response objects that follow
the 2.0 spec, offering a more structured protocol than REST. Some
agents advertise only JSON-RPC, while others advertise both. The
[`LLM::A2A::Card#interfaces`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A/Card.html#interfaces)
method lists which transports a remote agent supports.

#### Notes

JSON-RPC request and response objects are typed and follow the 2.0
spec. The
[`LLM::A2A.jsonrpc`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html#jsonrpc-class_method)
transport provides structured message envelopes rather than plain
HTTP.

### Tasks

#### Overview

A message to a remote agent starts a task, and the task is how the
exchange is tracked: its state, its artifacts, and the events it
emits. [`LLM::A2A`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html)
sends messages, and opens the task operations through
`LLM::A2A#tasks`.

#### How it works

`send_message` sends text and returns the response, whose `task` is the
task that was started. `send_streaming_message` takes a block that is
called for each event as the task progresses. The `tasks` object reads
and controls a task by id:

```ruby
require "llm"

a2a  = LLM::A2A.rest(url: "https://agent.example.com")

res  = a2a.send_message("What is the weather in Tokyo?")
task = res.task

a2a.tasks.get(task.id)       # the task's current state
a2a.tasks.list               # tasks the agent is tracking
a2a.tasks.cancel(task.id)    # ask the agent to stop

a2a.send_streaming_message("Write a report") do |event|
  puts event.inspect
end

a2a.tasks.subscribe(task.id) do |event|
  puts event.inspect
end
```

#### Why would I use it?

Working with tasks keeps a long exchange observable. You can read a
task's state, list the tasks an agent is tracking, cancel one, or
follow its updates, instead of waiting on a single final answer.

#### Notes

`send_streaming_message` yields one
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html) per
event: a task, a message, a status update, or an artifact update.
`tasks.subscribe` follows an existing task the same way. Both are only
useful when the remote agent advertises streaming, which its card
reports.

### Notifications

#### Overview

An A2A agent can push task updates to a URL you own, so a long task
does not have to be polled. The push notification configuration is
managed through `LLM::A2A#notifications`.

#### How it works

Register a webhook for a task, then read, list, or remove it. Each
operation takes the task id, and the identifier operations also take
the configuration id that `create` returns:

```ruby
config = a2a.notifications.create(
  task.id,
  url: "https://example.com/a2a/webhook",
  token: "shared-secret"
)

a2a.notifications.list(task.id)
a2a.notifications.get(task.id, config.id)
a2a.notifications.delete(task.id, config.id)
```

#### Why would I use it?

Push notifications turn a polled task into an event. The remote agent
posts to your URL when the task changes, so your code reacts to it
instead of calling `tasks.get` on a timer.

#### Notes

The `token` is sent with every notification so the receiver can verify
the sender. `authentication` and `id` are optional; when `id` is
omitted the agent assigns one, which `create` returns.

