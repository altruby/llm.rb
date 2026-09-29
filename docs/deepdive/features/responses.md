
## Responses

### Introduction

#### Overview

OpenAI's Responses API gives every reply an id, and a later call can
continue from one by passing `previous_response_id:`. When the provider
is asked to store the reply, it keeps the history, so a client can hand
the thread back instead of resending it.

#### How it works

Create a response with `llm.responses.create`, then continue it by
passing `previous_response_id:` the id of the last one. A response can
be read back with `get` and removed with `delete`:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])

first  = llm.responses.create "Your task is to answer the user's questions",
                              role: :developer
second = llm.responses.create "5 + 5 = X ?",
                              role: :user,
                              previous_response_id: first.id

puts second.content

llm.responses.get(second)     # read it back
llm.responses.delete(second)  # remove it
```

`create` accepts the same prompt shapes as a completion (a string or a
list), plus `role:`, `model:`, `tools:`, and a `stream:` target. It
returns an `LLM::Response` like any other call.

#### Why would I use it?

Server-side state means the conversation lives with the provider
instead of in the request. Passing one id continues a thread without
rebuilding and resending the messages, which keeps requests small and
lets a client that lost its local history pick the thread back up.

#### Notes

Only OpenAI implements the Responses API. A context in `mode:
:responses` uses this endpoint and defaults to `store: false`, so the
conversation is not kept on the provider and the context rebuilds the
input itself; set `store: true` to keep it there and have the next turn
continue with `previous_response_id`. A plain `llm.responses.create`
call continues only when `previous_response_id:` is given.
