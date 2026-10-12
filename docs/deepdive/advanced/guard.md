
## Guard

### Introduction

#### Overview

[`LLM::Guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html)
is the superclass for context-level supervisors. A guard is bound
to a context and inspects each pending tool call before it runs.
It can let the call through, cancel it, block it with an error, or
answer for it with a synthesized result. Guards handle policy,
validation, quotas, cost control, caching, and approval workflows.

#### How it works

A guard is a subclass of
[`LLM::Guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html)
that implements
[`LLM::Guard#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html#call-instance_method).
The guard is stamped onto the functions the context binds, and when a
function's task runs the guard is checked on the calling thread before
the tool is handed to the strategy. `call` receives the pending
`function:` and returns an
[`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
to close that single call, or `nil` to let it run. The guard inspects
the current conversation through the `messages` helper and reads the
pending call through the function's own accessors.

Configure a guard by passing a class through the `guard:` option;
options given in `guard_options:` are forwarded to `call` as keyword
arguments:

```ruby
class RateLimitGuard < LLM::Guard
  def call(function:, limit: 10)
    if messages.count(&:tool_return?) >= limit
      function.return(error: true, type: "guard_error",
                      message: "too many tool calls")
    end
  end
end

agent = LLM::Agent.new(
  llm,
  guard: RateLimitGuard,
  guard_options: {limit: 3}
)
agent.talk "Research the market", tools: [FetchNews, FetchStocks]
```

#### Why would I use it?

A guard is the one hook that sees every pending tool call and the
full conversation at once. It can observe what the model is about
to do, cancel a call that needs approval, block one that violates
policy, answer a cheap question without running a tool, or stop
work when a budget is spent. Because the guard runs before the
tool, anything it intercepts never executes.

#### Notes

[`LLM::Guard::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard/Null.html)
is the default guard for
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html);
it never blocks tool work.
[`LLM::Context#guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#guard-instance_method)
returns the configured guard class. Because `call` returns an
[`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
rather than a warning string, a guard can block an individual tool
call while the rest of the batch still executes. The guard is stamped
onto every function the context binds, so it runs whenever a task is
spawned, including tool calls a stream queues itself during a
streaming turn. A blocked call yields its return without executing.

The runtime creates a guard instance for each batch of tool calls and
stamps it onto the functions in that batch, so the same instance sees
every call in a batch. State in an instance variable therefore lasts
for the batch, but not from one batch to the next. Anything a guard
needs to remember across batches, like how many calls already ran,
must come from the conversation (`messages`) or from class-level
state.

### Inspect

#### Overview

The guard receives the pending
[`LLM::Function`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html)
and can read what the model is about to do before anything runs.
The function exposes its `name`, `arguments`, and parameter schema,
so a guard can base its decision on the actual call rather than on
the whole conversation. The guard also holds the context, so the
message history, token usage, and cost are visible too.

#### How it works

When you want to inspect a pending call before it runs, read the
function's accessors inside `call`.
[`LLM::Function#name`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#name-instance_method)
is the tool name, and
[`LLM::Function#arguments`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#arguments-instance_method)
is an
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
with the parsed arguments. The full parameter schema is available
through
[`LLM::Function#params`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#params-instance_method).
Returning `nil` lets the call run, so an inspection-only guard is a
pure observer:

```ruby
class AuditGuard < LLM::Guard
  def call(function:)
    warn "pending: #{function.name}(#{function.arguments.inspect})"
    nil  # let it run
  end
end
```

#### Why would I use it?

Inspecting the pending call is the basis for policy, validation,
and audit. A guard can log every call into a telemetry stream, or
reject a single call because its arguments violate a rule while
letting every other call through. The same read underpins the
richer decisions in the rest of this document.

#### Notes

The guard sees the parsed arguments exactly as the model requested
them. Reading them costs nothing and never executes the tool.
Returning `nil` means the call proceeds normally.

### Cancel

#### Overview

Cancelling is distinct from blocking with an error.
[`LLM::Function#cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#cancel-instance_method)
produces a return the model reads as a declined call, not a failed
one. The conversation stays honest: the model asked for something,
and the runtime declined it with a reason.

#### How it works

When you want to cancel a single pending call, call the
[`LLM::Function#cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#cancel-instance_method)
method with a `reason:` and return the result from `call`. The
pending call never executes, and the rest of the batch still runs.
A guard can cancel one call in a two-call batch and the other call
still executes:

```ruby
class ApprovalGuard < LLM::Guard
  def call(function:)
    if function.name == "delete-file"
      function.cancel(reason: "delete requires human approval")
    end
  end
end
```

#### Why would I use it?

Cancellation suits approval workflows and environment rules. A call
that needs a human in the loop, a tool that is disabled for a
particular user, or an operation that must not run in production
can all be declined without pretending the tool failed. Because
cancellation is per call, it declines only the offending tool and
leaves the rest of the batch intact.

#### Notes

The model receives
`{cancelled: true, reason: "delete requires human approval"}` as
that call's result and can react, for example by asking for
permission or skipping the operation. A cancelled call still counts
as resolved, like any tool return, so the model keeps moving. The
reason string is what the model sees, so write it as guidance
("ask the user first") rather than a raw error dump.

### Block

#### Overview

Blocking is how a guard enforces policy. A blocked call never runs,
and the model receives an in-band error explaining why. Unlike a
cancellation, an error tells the model the tool could not produce
a result at all.

#### How it works

When you want to block a call, return an
[`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
with `error: true`. The `type` and `message` are free-form, and the
model sees them inside the return value. Returning `nil` lets the
call through:

```ruby
class PolicyGuard < LLM::Guard
  def call(function:)
    if function.name == "exec"
      function.return(error: true, type: "policy_error",
                      message: "exec is disabled")
    end
  end
end
```

#### Why would I use it?

Blocking denies a dangerous tool, rejects an out-of-policy
argument, or stops a quota violation before it happens. The model
receives the return and can adapt, so the conversation stays valid.

#### Notes

A blocked call never executes. The return it produces is sent back
through the model like any tool result, so the model sees why the
call was blocked and can change course.

### Answer

#### Overview

A guard's return is injected into the conversation as if the tool
had executed, so a guard can answer for a tool that never runs.
From the model's side, a synthesized result is indistinguishable
from a real one.

#### How it works

When you want to answer a pending call yourself, return a value
through the
[`LLM::Function#return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html)
helper. The value you pass becomes the tool's result as-is, so it
must look like a plausible answer:

```ruby
class CacheGuard < LLM::Guard
  CACHE = {"get-weather:tokyo" => {forecast: "sunny"}}

  def call(function:)
    key = "#{function.name}:#{function.arguments[:city]}"
    function.return(CACHE[key]) if CACHE.key?(key)
  end
end
```

#### Why would I use it?

Standing in for a tool is how you cache expensive calls, mock tools
in tests, or degrade gracefully when a service is down. The same
hook can return a fixed answer for tools that should not run in a
given environment.

#### Notes

[`LLM::Function#unavailable`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html)
marks a tool as not found, and
[`LLM::Function#budget_spent`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html)
reports that the tool budget is exhausted. Both are returns too,
so they flow back to the model like any tool result. A guard that
synthesizes a result runs instead of the tool, so side effects the
tool would have performed, like a database write, are skipped.

### Budget

#### Overview

A guard can read the accumulated usage and cost of the conversation
through the context. That makes it the natural place to enforce a
hard ceiling: stop calling tools once a cost or token budget is
spent, or once the context window is nearly full.

#### How it works

When you want to enforce a budget, compare
[`LLM::Context#usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#usage-instance_method)
or
[`LLM::Context#cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#cost-instance_method)
against a limit inside `call`. Pass the limit through
`guard_options:` so it can be tuned per context. Returning a
cancellation or an error closes the call before it runs:

```ruby
class BudgetGuard < LLM::Guard
  def call(function:, limit: 0.05)
    if ctx.cost.total >= limit
      function.cancel(reason: "cost ceiling reached, ask before continuing")
    end
  end
end

ctx = LLM::Context.new(
  llm,
  guard: BudgetGuard,
  guard_options: {limit: 0.01}
)
```

#### Why would I use it?

Budgets matter for long autonomous runs where the model decides how
many tools to call. A cost ceiling keeps a runaway agent from
spending money, and a quota derived from `messages` (as in the
rate-limit example above) keeps a single user from exhausting
shared resources. The same comparison works with
[`LLM::Context#usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#usage-instance_method)
against
[`LLM::Context#context_window`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_window-instance_method)
to keep the conversation inside the model's window.

#### Notes

The cost reported by
[`LLM::Context#cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#cost-instance_method)
reflects the conversation so far, so a limit is enforced per call:
once the ceiling is crossed, the next pending call is declined. The
guard is not a replacement for
[`LLM::Agent.tool_budget`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#tool_budget-class_method),
which caps the number of tool calls in a single turn. The two
compose: the budget caps call count, and a guard enforces cost.
