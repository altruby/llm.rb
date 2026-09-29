## Model registry

### Introduction

#### Overview

The model registry is a catalog of every model each provider offers,
shipped with llm.rb under `data/<provider>.json`. The data is sourced
from [models.dev](https://models.dev) and powers cost estimation,
context-window limits, and the `/model` auto-complete in the console.

[`LLM::Registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html)
exposes that catalog, and
[`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
represents a single model's record. A `Model` is comparable **by price**,
so you can sort a provider's whole catalog from cheapest to most
expensive. This document covers reading the registry directly; the
runtime uses the same data when it estimates the cost or context window
of a conversation.

#### How it works

Get a registry with
[`LLM::Registry.for`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#for-class_method)
and a provider name, or through
[`LLM::Provider#registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#registry-instance_method).
[`LLM::Context#registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#registry-instance_method)
and
[`LLM::Agent#registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#registry-instance_method)
delegate to their provider's registry, so
[`LLM::Registry#keys`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#keys-instance_method)
returns the model names, and
[`LLM::Registry#models`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#models-instance_method)
returns the full
[`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
objects:

```ruby
require "llm"

registry = LLM::Registry.for(:openai)
registry.keys             # => ["gpt-image-2", "gpt-5.2-pro", ...]
registry.models           # => [LLM::Registry::Model, ...]
registry.models.map(&:id) # => same names as #keys
```

Use *`keys`* when you only need model names, and *`models`* when you want
to inspect pricing, limits, or capabilities.

#### Why would I use it?

The registry lets you discover what a provider offers without
hardcoding model names. Build a model picker, validate a model, check a
context window, or price a request. Because a
[`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
is comparable by price, you can also sort a provider's catalog and offer
only the cheapest models that still meet a requirement.

#### Notes

Each provider ships a `data/<provider>.json` registry file. A missing
model raises `LLM::NoSuchModelError`, and a missing registry raises
`LLM::NoSuchRegistryError`. The runtime rescues both to degrade
gracefully, so an unknown model's context window reads as `nil` rather
than crashing your code.

### Reading models

#### Overview

[`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
wraps one model record and exposes its identity, pricing, limits,
capabilities, and modalities.

#### How it works

Pick a model from
[`LLM::Registry#models`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#models-instance_method)
and call its readers. Note that the raw `cost`, `limit`, and `modalities`
readers return
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
metadata objects, while the convenience accessors return plain values:

```ruby
require "llm"

registry = LLM::Registry.for(:openai)
model    = registry.models.find { _1.id == "gpt-4.1" }
model.id # => "gpt-4.1"
model.name # => "GPT-4.1"
model.context_window # => 1_047_576
model.input_cost # => 2.0   (per million input tokens)
model.output_cost # => 8.0   (per million output tokens)
model.cost # => #<LLM::Object ...>  raw pricing
model.limit # => #<LLM::Object ...>  raw limits
model.modalities # => #<LLM::Object ...>  raw input/output lists
```

#### Why would I use it?

Pricing and limits are what most applications need from a catalog.
`input_cost` and `output_cost` let you compare models by spend without
unwrapping the raw cost object, and `context_window` tells you how large
a conversation a model can hold. That is exactly the data the runtime
uses to estimate cost and track context usage.

#### Notes

`name` falls back to `id` when a model has no human-readable name.
`input_cost` and `output_cost` return `nil` when a model is unpriced.
`context_window` returns `nil` when the limit is unknown, so it is safe
to compare against numbers.

### Capabilities

#### Overview

[`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
exposes a model's capabilities through predicate methods, so you can
filter a provider's catalog by what you need before you even make a
call.

#### How it works

Capability predicates return booleans for whether a model supports tool
calls, structured output, reasoning, or open weights:

```ruby
require "llm"

model = LLM::Registry.for(:openai).models.find { _1.id == "gpt-4.1" }
model.tool_call?         # => true  can be called as a tool
model.structured_output? # => true  supports typed output
model.reasoning?         # => false not a reasoning model
model.open_weights?      # => false weights are not public
```

#### Why would I use it?

Not every model supports every feature. If you are building a model
picker, filter the registry to models that support tool calls and
structured output before offering them to a user, and only include
reasoning models where you want the extra capability (and cost).

#### Notes

Capabilities vary per model and per provider, and are absent from some
records. The predicates coerce a missing flag to `false`, so you never
need a `nil` check.

### Modalities

#### Overview

Modalities describe what a model can read as input and produce as
output: text, image, audio, video, and PDF. A model is multimodal when
it handles more than text.

#### How it works

A model offers direction-aware tests and a set of convenience
predicates. `input?("pdf")` asks whether the model *reads* PDFs,
`output?("image")` whether it *produces* images, and `image?`/`audio?`/
`pdf?`/`video?` report support on either side:

```ruby
require "llm"

model = LLM::Registry.for(:openai).models.find { _1.id == "gpt-4.1" }
model.text?            # => true  reads and writes text
model.image?           # => true  reads or produces images
model.pdf?             # => true  reads or produces PDFs
model.audio?           # => false
model.input?("pdf")    # => true  reads PDFs as input
model.output?("image") # => false does not produce images
```

#### Why would I use it?

`text?` is a quick way to identify a general-purpose chat LLM as opposed
to a single-purpose generation model (such as a speech or image model),
and the per-modality tests let you find a model that can accept a PDF or
produce audio.

#### Notes

The `supports?`-style convenience predicates (`image?`, `audio?`, `pdf?`,
`video?`) return `true` when the model handles a modality in *either*
direction, so a model that only reads PDFs and writes text still reports
`pdf?` as `true`.

### Sorting by price

#### Overview

[`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
is `Comparable` by price, so sorting a provider's models orders them
from cheapest to most expensive.

#### How it works

Call `sort` on
[`LLM::Registry#models`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#models-instance_method).
Ordering compares input cost first, then output cost. Unpriced models
sort to the end:

```ruby
require "llm"

reg = LLM::Registry.for(:openai)
list = reg.models.sort
list.first.id # => "text-embedding-3-small"
list.last.id  # => "gpt-image-1" (unpriced sorts last)
```

#### Why would I use it?

Offering the cheapest capable model is a common product decision. Sort
by price, then filter to models that satisfy your capability and
modality requirements, and take the first.

#### Notes

Models without a price are treated as the most expensive so they sort
last rather than first. If you only compare a handful of models, the
`<` comparison works directly (`cheap < expensive` returns `true` when
`cheap` is cheaper).

### Raw lookups

#### Overview

[`LLM::Registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html)
also offers direct `model:` keyed lookups that resolve a single model and
return its raw metadata object.

#### How it works

[`LLM::Registry#cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#cost-instance_method),
[`LLM::Registry#limit`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#limit-instance_method),
and
[`LLM::Registry#modalities`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#modalities-instance_method)
take a `model:` keyword and return the corresponding raw
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html).
These lookups also apply fallback resolution, so a dated or numbered
model id matches its base model:

```ruby
require "llm"

registry = LLM::Registry.for(:openai)
registry.limit(model: "gpt-4.1").context # => 1_047_576
registry.cost(model: "gpt-4.1-2025-01-01") ==
  registry.cost(model: "gpt-4.1") # => true, dated id falls back
```

#### Why would I use it?

These methods are convenient when you already know a model's id and only
want one piece of raw metadata, and they are what the runtime itself
uses internally. For richer access, prefer the
[`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
objects from
[`LLM::Registry#models`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#models-instance_method).

#### Notes

A missing model raises `LLM::NoSuchModelError`. The fallback matching
strips date suffixes (`-YYYY-MM-DD`) and collapses numbered OpenAI ids
(`gpt-N-XXXX` → `gpt-N`) so a slightly out-of-date model id still
resolves.