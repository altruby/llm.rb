
## MCP

### Introduction

#### Overview

The Model Context Protocol (MCP) connects agents to external tools
and data sources through a standardized interface. Instead of
wiring each service directly into your agent, you run an MCP
server that exposes its capabilities. The runtime translates the
server's tool list into
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
subclasses the model can call.

#### How it works

The stdio transport runs the server as a child process and
communicates over stdin/stdout. Use
[`LLM::MCP#session`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#session)
to avoid launching the same process multiple times.

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
mcp   = LLM::MCP.stdio(argv: ["npx", "-y", "@forgejo/mcp-server"])
agent = LLM::Agent.new(llm)

mcp.session do
  agent.talk "What's happening on forgejo?", tools: mcp.tools
end
```

#### Why would I use it?

MCP decouples tool implementation from the agent. Add tools by
launching a new MCP server. Update them by restarting an existing
one. Remove them without touching the agent's code.

#### Notes

For stdio, use
[`LLM::MCP#session`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#session)
to avoid launching the same process multiple times. For HTTP,
[`LLM::MCP#session`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#session)
carries little benefit.

### HTTP

#### Overview

The HTTP transport connects to a remote MCP server over HTTP.
It is the right choice for cloud-hosted servers like GitHub's
MCP endpoint. Tools exposed by the server become
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
subclasses the model can call. The server does not need to run
locally or even on the same machine. Configure headers for
authentication and pick a transport backend for connection
management.

#### How it works

When you want to connect to a remote MCP server, provide a URL and
optional headers. The server's tool list is fetched and translated
into
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) subclasses the model can call.

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
mcp   = LLM::MCP.http(
  url: "https://api.githubcopilot.com/mcp/",
  headers: {
    "Authorization" => "Bearer #{ENV.fetch('GITHUB_PAT')}"
  },
  transport: :net_http_persistent
)
agent = LLM::Agent.new(llm)
agent.talk "What's happening on GitHub?", tools: mcp.tools
```

#### Why would I use it?

The HTTP transport connects to remote MCP servers. This matters
when the server is not running locally or when tools are maintained
by a different team and exposed as a service.

#### Notes

For HTTP,
[`LLM::MCP#session`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#session)
carries little benefit.

##### Persistent connections

Set `persistent: true` to reuse HTTP connections across requests
to the same MCP server. This uses
[`Net::HTTP::Persistent`](https://github.com/drbrain/net-http-persistent)
under the hood and avoids the overhead of opening a new TCP
connection for every request.

```ruby
mcp = LLM::MCP.http(
  url: "https://api.githubcopilot.com/mcp/",
  headers: {"Authorization" => "Bearer #{ENV.fetch('GITHUB_PAT')}"},
  persistent: true
)
```

### Prompts

#### Overview

An MCP server can offer prompts as well as tools: reusable,
parameterized message templates a client fetches and sends to a model.
[`LLM::MCP#prompts`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#prompts)
lists them, and
[`LLM::MCP#find_prompt`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#find_prompt)
fetches one and returns its messages.

#### How it works

`prompts` returns one
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
per prompt, carrying its name, description, and arguments.
`find_prompt` takes a `name:` and, for a prompt that declares
arguments, an `arguments:` hash, and returns an `LLM::Object` whose
`messages` are
[`LLM::Message`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html)
objects ready to send:

```ruby
require "llm"

mcp = LLM::MCP.stdio(argv: ["npx", "-y", "@forgejo/mcp-server"])

mcp.session do
  mcp.prompts.each { puts _1.name }

  prompt = mcp.find_prompt(name: "review", arguments: {path: "lib/llm.rb"})
  prompt.messages.each { puts "#{_1.role}: #{_1.content}" }
end
```

#### Why would I use it?

Prompts let a server ship the wording of a task, not just the tools to
carry it out. Fetching one keeps that wording in the server that owns
it, so it can change without a client release.

#### Notes

`find_prompt` adapts each message's content to the runtime's shape: a
text item becomes a string, and anything else stays an `LLM::Object`
under `original_content`.
[`LLM::MCP#get_prompt`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#get_prompt)
is an alias. Like `tools`, both methods borrow a session when one is
not already running.

