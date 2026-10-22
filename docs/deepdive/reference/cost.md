
## LLM::Cost

### Introduction

#### Overview

[`LLM::Cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html)
represents the approximate cost of a conversation. It breaks the
total down by token type, so you can see how much was spent on input,
output, cached tokens, reasoning, audio, and images. Cost is computed
from token usage and the pricing data shipped in the
[model registry](../reference/model_registry.md).

#### How it works

When you want to know what a conversation cost so far, call
[`LLM::Context#cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#cost-instance_method)
(or
[`LLM::Agent#cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#cost-instance_method))
and read the breakdown. The console shows this live in its status bar
after every turn:

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm)
ctx.talk "Hello"

cost = ctx.cost
cost.input    # => 0.0000042
cost.output   # => 0.0000084
cost.total    # => 0.0000126
cost.to_s     # => "0.00"
```

#### Why would I use it?

Cost tracking matters in production. Monitoring spend per
conversation, per agent, or per provider tells you which workflows
are expensive and when to switch models. Log a structured breakdown
with
[`LLM::Cost#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#to_h-instance_method),
or read
[`LLM::Cost#total`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#total-instance_method)
for a single number.

#### Notes

Cost is an approximation based on the pricing in the
[model registry](../reference/model_registry.md).
[`LLM::Cost.from`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#from-class_method)
returns an empty cost when the model or registry cannot be found, so
a missing model never crashes your code.

### Reading the breakdown

#### Overview

[`LLM::Cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html)
exposes each cost component as a reader, plus
[`LLM::Cost#total`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#total-instance_method),
[`LLM::Cost#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#to_h-instance_method),
and
[`LLM::Cost#to_s`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#to_s-instance_method).

#### How it works

Each component is a Float, and defaults to `0` when no tokens of
that type were used. The
[`LLM::Cost#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#to_h-instance_method)
method returns a Hash with every component and the total:

```ruby
cost = ctx.cost

cost.input
cost.output
cost.cache_read
cost.cache_write
cost.reasoning
cost.input_audio
cost.output_audio
cost.input_image

cost.to_h  # => {input: 4.2e-06, output: 8.4e-06, cache_read: 0.0,
           #     cache_write: 0.0, input_audio: 0.0, output_audio: 0.0,
           #     input_image: 0.0, reasoning: 0.0, total: 1.26e-05}
```

#### Why would I use it?

The per-component breakdown shows where the money goes. High cache
read costs suggest a conversation benefits from prompt caching.
High reasoning costs point at a model that thinks a lot. Log
[`LLM::Cost#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#to_h-instance_method)
at the end of a session to keep a spend trail.

#### Notes

[`LLM::Cost#to_s`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#to_s-instance_method)
returns the total in a compact, human-friendly format, rounded to
two decimals (`"0.01"`). Components that were not used are `0`, so
you never need to check for `nil` when aggregating.

The console renders context usage as a proportion, not a cost.
[`LLM::Context#context_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_usage-instance_method)
returns a `Rational` of the tokens used over the context window
(for example `Rational(100, 10_000)`), or `nil` when the window is
unknown or the conversation is too short.

### Token usage

#### Overview

[`LLM::Usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Usage.html)
holds the token counts a provider reports for a request: input,
output, reasoning, cache read, cache write, and the audio and image
tokens where a model supports them, with
[`LLM::Usage#total_tokens`](https://r.uby.dev/api-docs/llm.rb/LLM/Usage.html#total_tokens-instance_method)
summing them. Cost is computed from it, and so is the console's context
meter.

#### How it works

Every context and agent exposes four readers, each answering a
different question:

```ruby
ctx.token_usage    # => LLM::Usage, summed over the whole conversation
ctx.context_used   # => tokens in the most recent assistant message
ctx.context_usage  # => Rational fraction of the context window in use
ctx.context_window # => the model's window, or nil when unknown
```

[`LLM::Context#token_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#token_usage-instance_method)
accumulates across the conversation and returns `LLM::Usage.zero`
before any provider usage has been recorded.
[`LLM::Context#context_used`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_used-instance_method)
is the live size of a single turn, which is what the context window
is really being spent on.
[`LLM::Context#context_window`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_window-instance_method)
reads the limit from the model registry, and
[`LLM::Context#context_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_usage-instance_method)
divides one by the other.

#### Why would I use it?

`token_usage` answers "what has this conversation cost so far", while
`context_used` and `context_usage` answer "how much room is left".
Showing both lets a user see spend and headroom without either number
being mistaken for the other.

#### Notes

`LLM::Context#usage` is an alias of `token_usage`, kept for
compatibility. `context_used` and `context_usage` return `nil` when
the model is unknown to the registry, or before the conversation has
an assistant message to measure. An agent delegates all four readers
to the context it wraps.
