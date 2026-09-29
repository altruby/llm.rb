
## Built-in tools

### Introduction

#### Overview

llm.rb ships with thirteen ready-made tools that cover the operations
a coding or system agent needs most: filesystem work, search, and
shell commands. Each tool is a subclass of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
with a name, description, and typed parameters, exactly like a tool
you would write yourself. Load the whole catalog with
`require "llm/tools"`.

#### How it works

When you want to attach every built-in tool to an agent, require
the catalog and pass the full set of subclasses as the `tools:`
option. The runtime registers each tool's schema and lets the model
decide when to call it.

```ruby
require "llm"
require "llm/tools"

llm   = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: LLM::Tool.subclasses)
agent.talk "List the files in this repository"
```

#### Why would I use it?

The built-in tools cover the operations a coding or system agent
needs most, so you rarely need to write your own. They also handle
edge cases correctly: subprocesses get timeouts, interrupts kill
the child process, and failed calls return structured errors
instead of crashing the conversation.

#### Notes

The tools that spawn subprocesses use the optional `test-cmd.rb`
gem for process management and interrupt handling. The gem is
required only when those tools load. Every tool returns a Hash with
an `ok:` key that tells the model whether the call succeeded.

### Filesystem

#### Overview

The filesystem tools let the model read, write, and edit files,
list and create directories, and move around the working tree.
The most distinctive is
[`LLM::Tool::EditFile`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/EditFile.html),
which replaces an exact snippet and verifies the match count:

```ruby
LLM::Tool::EditFile.new.call(
  path: "config.yml",
  before: "port: 3000",
  after:  "port: 4000"
)
# => {ok: true, replaced: 1}
```

#### How it works

Each filesystem tool takes a path and returns a result Hash. The
`read-file` tool reads a whole file by default and accepts `start:`
and `stop:` to read a range of lines instead, returning the content
as `{lineno:, content:}` lines with a `truncated:` flag. A reversed
range (`start: 20, stop: 2`) is swapped to read lines 2 through 20.
The `edit-file` tool counts occurrences of `before` and raises unless
the count matches `expected_count`, which defaults to 1.

| Tool | Name | Parameters | Purpose |
|---|---|---|---|
| [`LLM::Tool::Pwd`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Pwd.html) | `pwd` | none | Report the current working directory |
| [`LLM::Tool::Ls`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Ls.html) | `ls` | `path`, `glob` | List files and directories, optionally matching a glob |
| [`LLM::Tool::Chdir`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Chdir.html) | `chdir` | `path` | Change the current working directory |
| [`LLM::Tool::Mkdir`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Mkdir.html) | `mkdir` | `path`, `max_bytes` | Create a tree of directories |
| [`LLM::Tool::ReadFile`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/ReadFile.html) | `read-file` | `path`, `start`, `stop`, `max_bytes` | Read a file, optionally a range of lines |
| [`LLM::Tool::WriteFile`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/WriteFile.html) | `write-file` | `path`, `content`, `newline` | Write a string to a file |
| [`LLM::Tool::EditFile`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/EditFile.html) | `edit-file` | `path`, `before`, `after`, `expected_count` | Replace an exact snippet in a file |

#### Why would I use it?

Reading source files to answer questions, writing new files, and
editing a snippet in place are the bread and butter of a coding
agent. The filesystem tools give the model all of it without you
writing a single tool.

#### Notes

The `chdir` tool changes the working directory for the whole
process, so subsequent file operations see the new directory. The
`mkdir` tool creates parent directories, like `mkdir -p`. The `ls`
tool raises when the path does not exist. The `read-file` tool
accepts `start:` and `stop:` line numbers and caps its output at
`max_bytes`, and the `write-file` tool appends a final newline by
default (`newline: false` opts out).

### Search

#### Overview

The search tools find things without reading the whole tree: `rg`
searches file contents, and `which` locates an executable on the
PATH. When a method name or a term is needed, the model searches
for it instead of guessing.

```ruby
LLM::Tool::Rg.new.call(patterns: ["def talk"], path: "lib")
# => {ok: true, stdout: "lib/llm/context.rb:42:def talk", stderr: "", duration: "0.0 seconds"}
```

#### How it works

When you want to search for one or more patterns, call the
[`LLM::Tool::Rg#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Rg.html#call-instance_method)
method with an Array of patterns, an optional `path:`, and a
`timeout:` in seconds. When you want to check whether a command is
installed, call the
[`LLM::Tool::Which#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Which.html#call-instance_method)
method with a `name:`.

| Tool | Name | Parameters | Purpose |
|---|---|---|---|
| [`LLM::Tool::Rg`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Rg.html) | `rg` | `patterns`, `path`, `timeout`, `max_count`, `max_bytes` | Recursively search for lines matching patterns |
| [`LLM::Tool::Which`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Which.html) | `which` | `name` | Locate an executable on the system PATH |

#### Why would I use it?

Search is how the model finds something without scanning files one
by one. Asked where a method is defined, the agent searches for it.
Before running a command, it checks with `which` that the binary
exists, and falls back to another approach when it does not.

#### Notes

The `rg` tool runs the ripgrep binary, so `rg` must be installed
and on the PATH. It refuses to search from the filesystem root and
rejects the pattern `.` to keep the model from dumping the entire
tree in one call. The `which` tool is pure Ruby: it scans the PATH
in order and returns the first directory that contains an
executable with the given name. When no match is found it returns
`{ok: false, path: nil}`.

### Command

#### Overview

The command tools run real subprocesses: arbitrary commands through
`exec`, Ruby code through `ruby`, commands inside a Bundler context
through `bundle`, and a fixed set of git subcommands through
`git`. All of them accept a `timeout:` and kill the child process
when the model interrupts the turn.

```ruby
LLM::Tool::Exec.new.call(
  arguments: ["bundle", "exec", "rspec", "spec/llm"],
  timeout: 30
)
```

#### How it works

When you want to run a command and capture its output, call the
[`LLM::Tool::Exec#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html#call-instance_method)
method with an `arguments:` array whose first element is the command
name. The `git` tool takes the same array, with a subcommand from a
fixed set as its first element, the `ruby` tool runs its code in a
fresh process, and the `bundle` tool runs a command under the
project's Bundler context. `bundle` uses the `BUNDLE_GEMFILE`
environment variable when set, or a `Gemfile` in the current working
directory otherwise, so the model can run project tools like `rspec`
or `rake` with the right gems loaded:

```ruby
LLM::Tool::Bundle.new.call(
  arguments: ["exec", "spec/llm"],
  timeout: 60
)
```

| Tool | Name | Parameters | Purpose |
|---|---|---|---|
| [`LLM::Tool::Exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html) | `exec` | `arguments`, `timeout` | Run a command without a shell |
| [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html) | `git` | `arguments`, `timeout` | Run a fixed set of git subcommands |
| [`LLM::Tool::Ruby`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Ruby.html) | `ruby` | `code`, `timeout` | Run a string of Ruby code |
| [`LLM::Tool::Bundle`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Bundle.html) | `bundle` | `arguments`, `timeout` | Run a command through `bundle` |

#### Why would I use it?

Running tests, inspecting git history, and executing a snippet of
Ruby are things a coding agent needs to do. The command tools make
those actions first-class, and the timeout keeps a hanging command
from stalling the conversation.

#### Notes

[`LLM::Tool::Exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html)
can be dangerous given a low-quality model. Gate it behind
[`LLM::Agent#confirm`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#confirm)
or manage the tool loop manually through
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html).
On interrupt, the running child process is killed. The `ruby` tool
uses the same Ruby that launched llm.rb. The `git` tool wraps the
subcommands `log`, `diff`, `commit`, `checkout`, `branch`, and `show`.
Each command tool also returns a `duration` field, a string such as
`"0.4 seconds"`, that reports how long the command ran.

### Bounded output

#### Overview

The built-in tools keep their returns from flooding the context
window. Each tool that can produce a large result accepts a
`max_bytes:` parameter, and its advisory class-level default
(`LLM::Tool::Exec.max_bytes`, `LLM::Tool::ReadFile.max_bytes`, etc.)
applies when none is given. `stdout` and `stderr` are each capped at
that limit, so a call can produce up to twice `max_bytes` of output.

#### How it works

The default is per tool, and it can be read or set on the tool class
itself. To raise one tool's cap, set it on that tool:

```ruby
LLM::Tool::ReadFile.max_bytes(175_000)   # raise read-file's default
LLM::Tool::Exec.max_bytes(150_000)       # raise exec's default
```

When you want to cap a single tool call below the default, pass
`max_bytes:` explicitly. The shared
[`LLM::Tool::Utils`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html)
helpers back this: [`spawn`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html#spawn-instance_method)
applies the limit to the command, [`truncate`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html#truncate-instance_method)
cuts a string and appends a `[truncated: ...]` marker, and [`truncate!`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html#truncate!-instance_method)
returns a `[content, truncated]` tuple for a caller that wants to
format the result itself:

```ruby
LLM::Tool::Exec.new.call(
  arguments: ["bundle", "exec", "rspec"],
  max_bytes: 20_000
)
```

#### Why would I use it?

A runaway command or a huge file read can otherwise dump more text
than fits the context window. Capping the output keeps the model
focused on what matters, and the marker lets it know more content
was available without re-requesting everything.

#### Notes

The per-tool `max_bytes` alone does not enforce anything; the built-in
tools use it through the `Utils` helpers. When you write your own
tool that returns a long string, cap it with `truncate` or `truncate!`
so a model cannot flood the window through your tool either.
