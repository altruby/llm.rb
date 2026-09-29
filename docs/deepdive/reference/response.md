
## LLM::Response

### Introduction

#### Overview

Every call returns an
[`LLM::Response`](https://r.uby.dev/api-docs/llm.rb/LLM/Response.html).
It is one normalized shape that a provider, an endpoint, or a context
extends with the accessors that response needs, so chat completions,
embeddings, images, and OCR all share a common surface without losing
their own.

#### How it works

`LLM::Response` carries the transport response and a little common
state: `#res` (the underlying HTTP response), `#body` (the parsed body,
or a raw string), `#ok?`, `#id`, and `#file?`. A name the base class
does not define falls through to the body, so a provider field such as
`content` is reachable directly.

A completion response also includes
[`LLM::Contract::Completion`](https://r.uby.dev/api-docs/llm.rb/LLM/Contract/Completion.html),
which adds the pieces a chat reply needs:

```ruby
res = agent.talk "Weather in Paris?", schema: Weather

res.content            # the raw text, or the structured reply
res.content!           # the reply parsed as an LLM::Object
res.messages           # the messages this turn produced
res.usage              # an LLM::Usage (input, output, reasoning, cache, ...)
res.reasoning_content  # the model's reasoning, when the provider exposes it
res.model              # the model that answered
```

#### Why would I use it?

One shape means one set of methods to learn: the same `content!`,
`usage`, and `messages` work whatever the provider. When an endpoint
returns something shaped differently, it adds an accessor rather than
changing the contract.

#### Notes

`#usage` returns an
[`LLM::Usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Usage.html), so
token counts are read the same way everywhere; the individual token
readers (`input_tokens`, `output_tokens`, `cache_read_tokens`, and so
on) live on the completion contract. Endpoint-specific accessors such
as `images`, `pages`, `audio`, or `embeddings` come from the adapter
that extends the response, so they are present only on responses that
carry that data. `#content!` parses the content as JSON, which is the
read to use with a schema.
