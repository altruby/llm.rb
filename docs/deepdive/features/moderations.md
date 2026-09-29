
## Moderations

### Introduction

#### Overview

A moderation classifies text or an image against a set of harm
categories, so an application can decide what to do with it before
showing it, storing it, or sending it to a model. OpenAI hosts the
moderation endpoint.

#### How it works

Call `llm.moderations` with the content to check. The response lists a
moderation per input, and each one reports whether it was flagged, the
categories it matched, and their scores:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])

res = llm.moderations.create(input: "I hate you")
mod = res.moderations[0]

mod.flagged?     # => true
mod.categories   # the categories that matched
mod.scores       # a score per category
```

`input` accepts a string or a URL, so an image URL is classified the
same way text is.

#### Why would I use it?

A moderation is a cheap check that runs before an expensive or public
step. Screen user-generated content before publishing it, gate a
request before it reaches a model, or keep a record of what was
filtered and why.

#### Notes

Only OpenAI implements moderations; another provider raises
`NotImplementedError`. The default model is `omni-moderation-latest`,
and it classifies both text and images. The scores are model
estimates, so a threshold is a product decision rather than a fixed
value.
