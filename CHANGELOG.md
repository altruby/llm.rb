> Changelog <br>
> [r.uby.dev](https://r.uby.dev) project

This file covers the v16 series. Releases up to and including v15 are kept in
[changelog/old.md](changelog/old.md).

## What's next

### Agent

* **agent: interrupt an agent via `LLM::Agent#id`** <br>
  The
  [`LLM.interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM.html#interrupt-class_method)
  method can interrupt an agent with nothing more
  than an ID that references it. A controller, a
  background job, or a socket handler can use this
  method to interrupt an agent that is running
  in the same process but on a different thread
  or fiber.

* **agent: add `LLM::Agent.registry`** <br>
  The
  [`LLM::Agent.registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#registry-class_method)
  method returns an object that holds every
  active instance of
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).
  An agent enters the registry when it starts a turn,
  and it exits the registry after that. The registry is
  thread-safe, local to a single process
  and
  [`LLM.interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM.html#interrupt-class_method)
  uses it under the hood to find an agent by ID.

### Function

* **function: `:ractor` raises `LLM::Interrupt` (like everyone else)** <br>
  An
  [`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
  that is delivered to a tool running on a ractor
  will travel back to the caller and raise itself
  on the caller's thread - the same as all other
  concurrency strategies. This only happens after
  all tools have been interrupted themselves, and
  it is the last step in an interrupt. The caller
  is expected to rescue `LLM::Interrupt` and handle
  the interrupt from there.

### Provider

* **deepseek: upload a file once and refer to it by id** <br>
  [`LLM::DeepSeek#files`](https://r.uby.dev/api-docs/llm.rb/LLM/DeepSeek.html#files-instance_method)
  returns an
  [`LLM::DeepSeek::Files`](https://r.uby.dev/api-docs/llm.rb/LLM/DeepSeek/Files.html)
  object now, so a file can be uploaded once and a later chat request can
  name it instead of resending its bytes. Before, the call raised
  `NotImplementedError`. Uploads default to `purpose: "user_data"` - the only
  purpose DeepSeek accepts - and requests go to the root of the API host,
  where DeepSeek serves its Files API.

### Tracer

* **tracer: add `LLM::Tracer#on_tool_interrupt`** <br>
  The [`LLM::Tracer#on_tool_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_interrupt-instance_method)
  method allows a tracer to close a span that
  was opened by
  [`LLM::Tracer#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_start-instance_method)
  and it is called for every tool that
  was interrupted. The callback receives
  the tool name and its tool call ID plus
  the span that was opened by `on_tool_start`.

* **tracer: return a span from `LLM::Tracer::Logger#on_tool_start`** <br>
  The
  [`LLM::Tracer::Logger#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html#on_tool_interrupt-instance_method)
  method now returns a span that can be
  matched by another callback method that
  will close the span (eg `on_tool_start -> on_tool_finish`).

* **tracer: return a span from `LLM::Tracer::PrettyLogger#on_tool_start`** <br>
  The
  [`LLM::Tracer::PrettyLogger#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html#on_tool_interrupt-instance_method)
  method now returns a span that can be
  matched by another callback method that
  will close the span (eg `on_tool_start -> on_tool_finish`).

* **tracer: add `LLM::Tracer::Logger#on_tool_interrupt`** <br>
  This method implements the new callback available on the
  superclass of Logger. The callback emits an `tool.interrupt`
  event and carries other metadata with it.

* **tracer: add `LLM::Tracer::PrettyLogger#on_tool_interrupt`** <br>
  This method implements the new callback available on the
  superclass of PrettyLogger. The callback emits a log entry
  that captures the tool interrupt via an IO object.

* **tracer: add `LLM::Tracer::Telemetry#on_tool_interrupt`** <br>
  This method implements the new callback available on the
  superclass of Telemetry. The callback emits an
  `gen_ai.tool.interrupt` event and closes the span
  that was opened by `on_tool_start`.

* **tracer: hear that `on_interrupt` is missing, instead of silence** <br>
  [`LLM::Tracer#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_interrupt-instance_method)
  raises `NotImplementedError` now, the way the other hooks do, so a tracer
  that never answered for an interrupt says so rather than dropping the
  ending in silence. [`LLM::Tracer::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Null.html)
  answers it, and a tracer opts out by answering with a no-op. The raise is
  contained by `LLM::Tracer::Rescue`, so the interrupt a caller was given is
  unchanged; the bundled loggers and `Telemetry` answer the tool ending but
  not this one, so an interrupt announced to one of them is reported on
  standard error.

* **tracer: make a missing `on_exit` visible** <br>
  `on_exit` raises `NotImplementedError` now, where it used to do nothing,
  and every bundled tracer answers it: `Telemetry#on_exit` flushes the spans
  it has not exported, and the others answer with a no-op. A custom tracer
  that leaned on the old default has the raise reported on standard error
  every time a turn ends, and answering the hook with a no-op is how it opts
  out.

* **tracer: keep a tracer bug from taking an agent down** <br>
  [`LLM::Tracer::Rescue`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Rescue.html)
  is prepended onto every subclass of `LLM::Tracer`, so a callback that
  raises is reported on standard error and the turn carries on. `LLM::Interrupt`
  is re-raised, because a cancel is not a tracer's to swallow, and an
  exception outside `StandardError` and `ScriptError` is left alone.
  `LLM::Tracer` itself is not covered, so a hook that raises on the base
  class still raises.

### LLM::Context

* **context: match a conversation to the row it is stored in** <br>
  [`LLM::Context#id`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#id-instance_method)
  takes the id of the record the context is bound to, when that id is a
  UUIDv7 string, so the conversation and its row share one value - in a log,
  in a tracer, or from either side of the pair. Before, a context always
  minted an id of its own, and nothing connected it to the row it came from.
  An explicit `id:` still wins, and a record whose id is an integer, a slug,
  or not saved yet still gets one of its own.

* **context: find out about a bad id where you gave it** <br>
  An `id:` that is not a UUIDv7 string raises `LLM::Error` at the call that
  passes it, rather than leaving a context whose `created_at` quietly answers
  `nil` - the id is what carries the creation time. The check is
  [`LLM::Utils.uuidv7?`](https://r.uby.dev/api-docs/llm.rb/LLM/Utils.html#uuidv7?-instance_method),
  which `LLM::Utils.timestamp` reads a UUIDv7 through instead of repeating
  the pattern and the version nibble itself. A payload the runtime wrote
  still restores as it was, so a context saved before this still loads.

## v16.0.0

Changes since `v15.5.0`.

This release makes an interrupt precise: `LLM::Interrupt` moves outside
`StandardError`, a turn between its requests ends where it is, and a cancel is
delivered inside the tool that has to handle it. It also requires Ruby 3.4 or
later, reads a `:jsonb` record's messages from the column, saves a
record-backed conversation after each request, and adds
`LLM::ActiveRecord#messages!`, `LLM::Stream#on_step`, and a tracer's
`on_interrupt` hook.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| Ruby 3.3 or later | Ruby 3.4 or later |
| `record.messages` returns the messages the runtime holds | a `:jsonb` record returns a relation of `LLM::ActiveRecord::Message` rows |
| a `set_tracer` method on an ORM model | `set tracer:` in the block, or `tracer:` on the wrapper |
| a pre-start cancel is dropped on `:thread`, `:fiber`, and `:async`, a `NoMethodError` on `:fork`, and says nothing on `:ractor` | the cancel is held, and delivered inside the tool's call |
| a cancel that arrives between two requests does nothing | the turn ends there, and the caller sees `LLM::Interrupt` |
| a bare `rescue`, or `rescue => ex`, catches a cancel | `LLM::Interrupt` is outside `StandardError`, so both forms pass it through |

* **drop Ruby 3.3 support** <br>
  The gem now requires Ruby 3.4 or later. Ruby 3.3 cannot hold an
  interrupt for a ractor-backed tool call, so a cancel can arrive
  before the tool starts and never be delivered.

* **activerecord: read a `:jsonb` record's messages from the column** <br>
  The `#messages` of a `:jsonb` record is now a relation over the stored
  messages, so a conversation can be filtered and counted in SQL without a
  provider or credentials. Before, every record loaded the runtime; reach
  that again with `#messages!`, and order the relation by `position`
  because it is unordered.

* **function: hold a cancel that arrives before the tool starts** <br>
  A cancel that arrived before the tool started used to be lost: dropped on
  `:thread`, `:fiber`, and `:async`, a `NoMethodError` on a `:fork` task that
  had not been spawned, and nothing at all on `:ractor`. It is now held until
  the call opens and delivered inside it, so the tool is entered, its own
  `rescue` sees the interrupt, and a caller that cancelled a task it had not
  yet spawned is answered with the cancel rather than a return. On `:async`
  and `:fiber` the raise is asked of the scheduler rather than issued, so a
  tool that never yields still answers, and that caller sees a return with the
  tool told it was asked about.

* **interrupt: reach a turn that is between its requests** <br>
  A cancel that arrived between two requests used to do nothing, because
  there was nothing in flight to close and nothing running to raise into.
  It now ends the turn where it is, raising `LLM::Interrupt` into the
  caller the turn runs under and announcing `scope: :agent` to the tracer
  first. `LLM::Agent#run_loop` records that caller for as long as the turn
  lasts, and it answers `interrupt!` through
  [`LLM::Agent::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent/Interrupt.html).
  The raise lands in the thread or fiber the turn runs on, so it unwinds out
  of the turn to whoever called it.

* **interrupt: move `LLM::Interrupt` outside `StandardError`** <br>
  `LLM::Interrupt` is now an `Exception` rather than an `LLM::Error`, so a
  bare `rescue` and a `rescue => ex` pass a cancel through instead of
  swallowing it. Before, a broad rescue in a tool, a tracer, or an
  application could eat an interrupt, and the turn looked like one that had
  ignored its cancel. It is not a `SignalException`, since an interrupt has
  to be catchable and a signal is a framework's own condition. A caller that
  handles a cancel names `LLM::Interrupt`; `#wait` and the tool's
  `on_interrupt` hook are unchanged, and a task still carries the interrupt
  back to the caller rather than raising it inside its reactor.

### ActiveRecord

* **activerecord: add `messages!` for the runtime's own messages** <br>
  [`LLM::ActiveRecord#messages!`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#messages!-instance_method)
  returns the messages the runtime holds, including state that has not been
  saved, where `#messages` reads the column. Use it to reach the live
  conversation of a `:jsonb` record. The Sequel plugin answers to
  `#messages!` too, where it is the same call as `#messages`.

### Agent

* **agent: keep the instructions it injected in step** <br>
  An agent now refreshes its instructions before each request, so a
  conversation restored from saved state runs on the agent's current
  instructions instead of the ones it was saved with. A message the caller
  composed is never touched.

* **agent: identify its own instructions by the mark, not by the role** <br>
  Fix a bug where an agent on Google added a fresh copy of its instructions
  every turn, because it looked for a `system` message and Google gives
  instructions the `user` role. It now marks the message it wrote and finds
  it by that mark.

### Console

* **console: erase with the backspace key on OpenBSD** <br>
  The console now erases for every code a backspace key sends: DEL (127),
  ^H (8), and curses's `KEY_BACKSPACE`. Before, only 127 worked, so
  backspace did nothing on the OpenBSD console.

### Fix

* **fork: require xchan.rb `~> 0.24`** <br>
  The `:fork` strategy now needs `xchan.rb` 0.24 or later, up from 0.23.

### Function

* **function: deliver an interrupt to the tool, not to whatever is running** <br>
  A cancel is now aimed at the tool on every concurrency strategy. A running
  tool is entered and
  [`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html) raised
  inside it, so its own `rescue` and its
  [`LLM::Tool#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_interrupt-instance_method)
  hook see it, whether the tool was given as an instance or a class. A cancel
  that arrives before the tool starts is held and delivered inside the call, and
  one that arrives after the tool returns is a no-op that leaves the result
  alone. Before, the raise landed wherever the target thread or fiber had got
  to, and a tool's hook ran on some strategies but not others. A pre-start
  cancel was dropped on `:thread`, `:fiber`, and `:async`, was a `NoMethodError`
  on `:fork`, and said nothing on `:ractor`. Three strategies keep a shape of
  their own: `:fiber` and `:async` ask the fiber scheduler for the raise, so a
  tool that never yields is one it cannot reach, and `:sequential` runs the tool
  in the caller's own thread, so it tells the tool through its hook alone.

* **function: answer a task that has already answered** <br>
  A second `#wait` is answered from what the first one took, which is what
  `Thread#value` does, so a task that has answered answers again. That covers an
  `:async` queue the first wait drained, a `:fork` channel the task closed, and
  a `:ractor` whose result is held by a ractor of the task's own rather than
  asked of the ractor that ran the tool and has gone. A group's cancel reaches
  every task it holds, and an interrupt re-raises the same exception rather than
  blocking. Before, a second wait blocked on a queue nothing would fill, or read
  a channel or ractor that had already closed.

* **function: answer a forked call that ended without a result** <br>
  A `:fork` tool that died before it wrote anything used to leave
  [`LLM::Function::Fork::Task#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Fork/Task.html#wait-instance_method)
  blocked on a read that never ended, because this side still held the write
  end of the same channel and so never saw end of file. Each side now closes
  the end it does not use, which makes that ending an `EOFError`, and `#wait`
  answers it in band rather than raising into the turn, the way the runtime
  answers a tool that raised: `{error: true, type: "EOFError", message: "the
  tool exited unexpectedly"}`. A second wait is given the same return.

* **function: refuse a `:fiber` scheduler that cannot hold a cancel** <br>
  The `:fiber` strategy now raises
  [`LLM::FiberError`](https://r.uby.dev/api-docs/llm.rb/LLM/FiberError.html) when
  `Fiber.scheduler` does not implement `fiber_interrupt`, because a cancel that
  arrives before the call is held by asking the scheduler for a raise at the
  call's first instruction. A scheduler that cannot be asked would be sent the
  cancel before the call instead, where the tool never runs, so the strategy
  refuses in the caller's hands, before a fiber is scheduled at all.

### ORM

* **orm: save a conversation after each request, not once per turn** <br>
  A record-backed conversation is now written down as it goes, so an
  interrupted turn can be continued instead of started over. Before, the
  wrappers saved once when the whole turn finished, so an interrupted turn
  persisted nothing.

* **orm: drop the `set_tracer` callback** <br>
  The wrappers no longer resolve a tracer from a `set_tracer` method on the
  model. Declare it where an agent's other defaults are declared, with
  `set tracer:` in the block, or pass it to the wrapper as `tracer:`, which
  is what a context has. A model that implements `set_tracer` today loses
  its tracer silently.

### Prompt

* **prompt: let a message carry fields a caller attaches to it** <br>
  [`LLM::Prompt#system`](https://r.uby.dev/api-docs/llm.rb/LLM/Prompt.html#system-instance_method),
  `#user`, `#developer`, and `#talk` (and its `#chat` alias) now take an
  `extra:` keyword, so a caller can tag a message with fields of its own. The
  runtime reads those fields back instead of guessing provenance from the role.

### Provider

* **deepseek: support image attachments in chat completions** <br>
  DeepSeek's vision models now accept an image. A `:image_url` object is sent
  as an `image_url` item, and a local image file as a base64 data URI.
  Anything else is rejected with a reason: a remote file or an `LLM::Response`
  raises
  [`LLM::PromptError`](https://r.uby.dev/api-docs/llm.rb/LLM/PromptError.html)
  because DeepSeek has no Files API, and a non-image local file raises because
  its models read images only.

* **provider: keep a scoped header alive through garbage collection** <br>
  Fix a bug where a header set by
  [`LLM::Provider#with`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#with-instance_method)
  could be collected before its block returned, so a garbage collection inside
  the block was enough to make a request later in the same scope go out without
  it. The store held the header hash weakly. It now holds it for as long as the
  provider is alive, so a scoped header lasts as long as the scope does.

### Registry

* **refresh model metadata** <br>
  Update `data/` with current listings, limits, and pricing. Anthropic adds
  Claude Sonnet 5.5, OpenAI adds GPT-6.1 Sol and the Daybreak Blue and Daybreak
  Red models, Bedrock adds Claude Sonnet 5.5, GPT-6 Sol, GPT-6 Luna, and GPT-6.1
  Sol across regions plus Grok 4.7 in the global and US regions, Alibaba adds
  the Qwen3.5, Qwen3.7, and Qwen3.8 Flash models, DeepInfra adds the Xiaomi
  MiMo V2.6 models and `tencent/Hy4-preview`, xAI adds Grok Imagine Video 1.5
  Lite, and OpenRouter adds ten models. OpenRouter drops six entries, Mistral
  drops `magistral-small`, and Google, DeepSeek, Moonshot, and Z.ai correct
  limits and prices.

### Schema

* **schema: apply every `parameter` option to the leaf** <br>
  Every option given to `parameter` now reaches the schema, so `min:`, `max:`,
  `multiple_of:`, and `const:` are no longer dropped, a `default: false`
  survives, and `required: false` marks a parameter optional. Before, only
  `required`, `default`, and `enum` were read, so a tool that declared a range
  sent a plain number and lost it.

### Stream

* **stream: add `on_step`, called when a request completes** <br>
  [`LLM::Stream#on_step`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_step-instance_method)
  is a new callback, fired once the prompt and response are in the
  conversation. It marks where one request ends and the next begins, which is
  where a stream can checkpoint, and it fires once per successful request even
  when streaming is off.

### Tools

* **tools: wait for a command's status, not only for it to stop running** <br>
  Fix a bug where an exec-backed tool could answer `ok: nil` for a command
  that ran and printed its output.
  [`LLM::Tool::Utils#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html#wait-instance_method)
  left as soon as `running?` said the process was gone, and the status is not
  decided at that moment, so `command.success?` was read before it had an
  answer. It waits for the status now, and a command that was never found is
  the exception, because there was nothing to reap.

### Tracers

* **tracer: report a request that failed** <br>
  [`LLM::Tracer#on_request_error`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_request_error-instance_method)
  is now called whenever a request ends without a response, so a span is always
  closed. Before, only provider errors that became exceptions were reported, so
  a dropped connection left a span open, which reads like a process that died.

* **tracer: add `on_interrupt`, called when a request is interrupted** <br>
  [`LLM::Tracer#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_interrupt-instance_method)
  is a new hook, called with `scope: :request`, `:tool`, or `:agent` before
  `LLM::Interrupt` reaches the caller, so a tracer can record an interrupted
  turn. An `:agent` scope means the interrupt landed between a turn's
  requests, where there was nothing more precise to interrupt. It does
  nothing by default, since a raise here would replace the interrupt
  callers are written against.

* **tracer: announce an interrupted tool phase once** <br>
  [`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait-instance_method)
  now calls `on_interrupt` once when an interrupt unwinds through it, rather
  than once per tool, matching the single exception the caller receives.
