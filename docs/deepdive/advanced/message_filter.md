
## MessageFilter

### Introduction

#### Overview

[`LLM::MessageFilter`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter.html)
is the superclass for message filters. A filter is bound
to a context and rewrites a single message before it is sent to the
provider. This lets you scrub sensitive data, inject context, or
otherwise modify outgoing messages without changing your prompt
code.

#### How it works

A filter is a subclass of
[`LLM::MessageFilter`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter.html)
that implements
[`LLM::MessageFilter#call`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter.html#call-instance_method).
The method receives the message to filter and returns a
message.
You can mutate the message in place or return a new one; either way,
the returned message is what gets sent.

Configure the filter on a context with the `filter:` option,
passing a class rather than an instance. The runtime instantiates it
once per turn. Options passed through `filter_options:` are
forwarded to `call` as keyword arguments. The filter runs on
the most recent message in both chat completions and Responses API
turns, before the request reaches the provider:

```ruby
class RedactEmails < LLM::MessageFilter
  def call(message:)
    content = message.content.to_s.gsub(/[\w.+-]+@[\w-]+\.[\w.]+/, "[EMAIL]")
    LLM::Message.new(message.role, content, message.extra)
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(
  llm,
  filter: RedactEmails
)
ctx.talk "Contact support@example.com for help"
```

#### Why would I use it?

Filters give you a single hook point for all outgoing messages.
Common uses include redacting PII before it leaves your process,
injecting a timestamp or request ID, or normalizing content for a
particular provider. Because the filter runs automatically on
every turn, you never need to remember to apply the rewrite in
your prompt code.

#### Notes

[`LLM::MessageFilter::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter/Null.html)
is the default filter; it returns the message unchanged. The
`filter_options:` hash is passed to `call` on every turn. Streams can
observe filtering through the
[`LLM::Stream#on_filter`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_filter-instance_method)
and
[`LLM::Stream#on_filter_finish`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_filter_finish-instance_method)
callbacks, which receive the filter instance.
