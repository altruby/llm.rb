
## Intercept

### Introduction

#### Overview

[`LLM::Intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html)
is the superclass for context-level supervisors. An intercept is bound
to a context and inspects each pending tool call before it runs. It
can let the call through, cancel it, block it with an error, or answer
for it with a synthesized result. Intercepts handle policy, validation,
quotas, cost control, caching, and approval workflows.

#### How it works

An intercept is a subclass of
[`LLM::Intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html)
that implements
[`LLM::Intercept#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html#call-instance_method).
It is stamped onto the functions the context binds, and when a
function's task runs the intercept is checked on the calling thread
before the tool is handed to the strategy. `call` receives the pending
`function:` and returns an
[`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
to close that single call, or `nil` to let it run. The intercept
inspects the current conversation through the `messages` helper and
reads the pending call through the function's own accessors.

Configure an intercept by passing a class through the `intercept:`
option; options given in `intercept_options:` are forwarded to `call`
as keyword arguments:

```ruby
class RateLimitIntercept < LLM::Intercept
  def call(function:, limit: 10)
    if messages.count(&:tool_return?) >= limit
      function.return(error: true, type: "intercept_error",
                      message: "too many tool calls")
    end
  end
end

agent = LLM::Agent.new(
  llm,
  intercept: RateLimitIntercept,
  intercept_options: {limit: 3}
)
agent.talk "Research the market", tools: [FetchNews, FetchStocks]
```

#### Why would I use it?

An intercept is the one hook that sees every pending tool call and the
full conversation at once. It can observe what the model is about to
do, cancel a call that needs approval, block one that violates policy,
answer a cheap question without running a tool, or stop work when a
budget is spent. Because the intercept runs before the tool, anything
it intercepts never executes.

#### Notes

[`LLM::Intercept::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept/Null.html)
is the default intercept for
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html);
it never blocks tool work.
[`LLM::Context#intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#intercept-instance_method)
returns the configured intercept. Because `call` returns an
[`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
rather than a warning string, an intercept can block an individual tool
call while the rest of the batch still executes. It is stamped onto
every function the context binds, so it runs whenever a task is
spawned, including tool calls a stream queues itself during a streaming
turn. A blocked call yields its return without executing.

The runtime builds an intercept instance for each turn and stamps it
onto the functions of that turn, so the same instance sees every call
in the turn. State in an instance variable therefore lasts for the
turn, but not from one turn to the next. Anything an intercept needs to
remember across turns, like how many calls already ran, must come from
the conversation (`messages`) or from class-level state.

`intercept:` also takes an instance rather than a class, which is how
[`LLM::Intercept.multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html#multi-class_method)
is attached: it asks each intercept it holds in turn and stops at the
first one that answers the call.

### Inspect

#### Overview

The intercept receives the pending
[`LLM::Function`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html)
and can read what the model is about to do before anything runs.
The function exposes its `name`, `arguments`, and parameter schema,
so an intercept can base its decision on the actual call rather than on
the whole conversation. The intercept also holds the context, so the
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
Returning `nil` lets the call run, so an inspection-only intercept is a
pure observer:

```ruby
class AuditIntercept < LLM::Intercept
  def call(function:)
    warn "pending: #{function.name}(#{function.arguments.inspect})"
    nil  # let it run
  end
end
```

#### Why would I use it?

Inspecting the pending call is the basis for policy, validation,
and audit. An intercept can log every call into a telemetry stream, or
reject a single call because its arguments violate a rule while
letting every other call through. The same read underpins the
richer decisions in the rest of this document.

#### Notes

The intercept sees the parsed arguments exactly as the model requested
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
An intercept can cancel one call in a two-call batch and the other
call still executes:

```ruby
class ApprovalIntercept < LLM::Intercept
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

Blocking is how an intercept enforces policy. A blocked call never
runs, and the model receives an in-band error explaining why. Unlike a
cancellation, an error tells the model the tool could not produce
a result at all.

#### How it works

When you want to block a call, return an
[`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
with `error: true`. The `type` and `message` are free-form, and the
model sees them inside the return value. Returning `nil` lets the
call through:

```ruby
class PolicyIntercept < LLM::Intercept
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

An intercept's return is injected into the conversation as if the tool
had executed, so an intercept can answer for a tool that never runs.
From the model's side, a synthesized result is indistinguishable
from a real one.

#### How it works

When you want to answer a pending call yourself, return a value
through the
[`LLM::Function#return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html)
helper. The value you pass becomes the tool's result as-is, so it
must look like a plausible answer:

```ruby
class CacheIntercept < LLM::Intercept
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
so they flow back to the model like any tool result. An intercept that
synthesizes a result runs instead of the tool, so side effects the
tool would have performed, like a database write, are skipped.

### Budget

#### Overview

An intercept can read the accumulated usage and cost of the
conversation through the context. That makes it the natural place to
enforce a hard ceiling: stop calling tools once a cost or token budget
is spent, or once the context window is nearly full.

#### How it works

When you want to enforce a budget, compare
[`LLM::Context#usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#usage-instance_method)
or
[`LLM::Context#cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#cost-instance_method)
against a limit inside `call`. Pass the limit through
`intercept_options:` so it can be tuned per context. Returning a
cancellation or an error closes the call before it runs:

```ruby
class BudgetIntercept < LLM::Intercept
  def call(function:, limit: 0.05)
    if context.cost.total >= limit
      function.cancel(reason: "cost ceiling reached, ask before continuing")
    end
  end
end

ctx = LLM::Context.new(
  llm,
  intercept: BudgetIntercept,
  intercept_options: {limit: 0.01}
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
once the ceiling is crossed, the next pending call is declined. An
intercept is not a replacement for
[`LLM::Agent.tool_budget`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#tool_budget-class_method),
which caps the number of tool calls in a single turn. The two
compose: the budget caps call count, and an intercept enforces cost.
