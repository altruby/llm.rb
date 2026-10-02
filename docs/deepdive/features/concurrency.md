
## Concurrency

### Introduction

#### Overview

llm.rb supports six concurrency strategies for tool execution:
`:sequential`, `:thread`, `:fiber`, `:async`, `:fork`, and
`:ractor`. Each implements the same interface
([`LLM::Function::Task#spawn`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#spawn),
[`LLM::Function::Task#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#wait),
[`LLM::Function::Task#alive?`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#alive?),
[`LLM::Function::Task#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#interrupt!)),
so the caller never has to care which
strategy is behind a given task.

#### How it works

Each strategy creates a task object that wraps a function call.
[`LLM::Function::Task#spawn`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#spawn)
starts execution,
[`LLM::Function::Task#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#wait)
collects the result,
[`LLM::Function::Task#alive?`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#alive?)
checks whether the task is still running, and
[`LLM::Function::Task#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#interrupt!)
signals the task to stop.

Interruption is reliable across all six.
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
reaches the tool regardless of whether it runs on a thread, fiber, process,
or ractor.

A tool can rescue
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
and return a structured error to cancel the tool call, or it can
re-raise to cancel the turn entirely. When you re-raise
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
or leave it unrescued the exception is raised on the caller's thread
and that effectively terminates the turn.

The main benefit of rescuing yourself is to let the tool clean up
and free lingering resources, but you usually want to re-raise so
the cancel request ends the turn. Otherwise the tool call is
intercepted but the turn continues.

```ruby
##
# At a high-level
agent = LLM::Agent.new(llm, concurrency: :fork, tools: [...])
agent.talk "Run the tools"

##
# At a low-level
fn = FetchStocks.function
fn.task(:thread).wait
```

#### Why would I use it?

Different tools have different execution requirements. IO-bound
tools benefit from thread or async concurrency. CPU-bound tools
benefit from ractors or forks. Tools that might crash the process
should run in a fork for isolation.

The common interface means you can change strategies without
changing your tool code.

The payoff is when the model orchestrates several tools at once.
When you give an agent a set of independent tools it can fan the
calls out across a strategy and synthesize the results, turning N
round trips into one. See
[Fan-out with tools](tools.md#fan-out-with-tools) for the pattern.

#### Notes

**sequential**: Tools run one at a time on the calling thread. No
overhead. Best for simple agents or when tool order matters.

**thread**: Each tool runs in its own Thread. Releases the GVL
during blocking IO. Best for IO-bound tools like HTTP calls and
database queries.

**fiber**: Each tool runs in a scheduler-backed Fiber. Requires
`Fiber.scheduler`. Best for IO-bound tools inside an async
framework. Much lighter than threads.

**async**: Each tool runs as an `Async::Task` inside a managed
background reactor. Best for IO-bound tools when you want Async's
structured concurrency model without running your whole application
inside a reactor. Requires the `async` gem.

**fork**: Each tool runs in a forked child process. True parallelism
and process isolation. Best for shell commands, native extensions,
or anything you do not want touching the parent's memory. Requires
the `xchan.rb` gem (`~> 0.24`).

**ractor**: Each class-based tool runs in a Ruby Ractor. True
parallelism without the overhead of forking full processes. Only
class-based tools are supported. Arguments must be ractor-shareable.

| Strategy | Backing | Parallel? | Isolation? | Requires |
|---|---|---|---|---|
| `:sequential` | direct call | No | No | None |
| `:thread` | `Thread` | IO only (GVL) | No | None |
| `:fiber` | `Fiber.schedule` | Cooperative | No | `Fiber.scheduler` |
| `:async` | `Async::Reactor` | Cooperative | No | `async` gem |
| `:fork` | `Kernel.fork` | Yes (process) | Yes (memory) | `xchan.rb` gem |
| `:ractor` | `Ractor` | Yes (CPU) | Limited | None |
