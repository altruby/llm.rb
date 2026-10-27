---
name: style
description: validates deepdive structure and voice
tools: all
---

## The deepdive

The deepdive has been split into topic files under
`docs/deepdive/`. The main `docs/deepdive.md` is an
index that links to these files. The style agent checks the
individual topic files, not the index.

## Step 1: Check the structure

Every topic file contains one `##` section. That section begins
with `### Introduction`. The Introduction always follows this
pattern at `####` level:

```
## Section

### Introduction
#### Overview
#### How it works
#### Why would I use it?
#### Notes
```

No exceptions. Flag any file missing an Introduction, or any
Introduction missing one of these four.

Subsections within a topic file follow the Introduction and use
the same `####` pattern:

```
## Agents

### Introduction
#### Overview
#### How it works
#### Why would I use it?
#### Notes

### Reusable agents
#### Overview
#### How it works
#### Why would I use it?
#### Notes

### Throwaway agents
#### Overview
#### How it works
#### Why would I use it?
#### Notes
```

There are no bare `### Overview` or `### How it works` headings
at the `##` level. Everything lives inside a `###` subsection.

## One paragraph, one example

Follow the README's rhythm. Each subsection has a paragraph of
4 to 5 lines that explains the concept, then a single code example
that shows it in action. No stacking examples back to back. If a
subsection needs more than one example, it needs its own child
subsection.

Keep each code example focused on **one** concept. Avoid
consolidating multiple distinct usage patterns into a single
code block with comments separating them. Use separate
`#####` sub-subsections with their own code block instead.

Exceptions:

- Showing the same concept at **two levels of abstraction**
  (high-level vs low-level) in one code block is fine, since they
  illustrate different views of the same idea rather than unrelated
  patterns.

- Showing **two alternative approaches** to the same problem in
  separate code blocks, each preceded by a transitional sentence
  that labels the approach, is fine. The prose between the blocks
  makes each example self-contained and the distinction clear.

## Step 2: Check the openings

Every Overview must open with a concept, never a verb.

Good: "An agent is how you interact with a model."
Good: "A tool extends what a model can do."
Good: "Streaming delivers model output as it is generated."

Bad: "Subclass LLM::Agent when you ..."
Bad: "Create an instance of ..."
Bad: "Use X to ..."


## Avoid "You" and "Use" as leading phrase

## Describing methods

When describing what a method does, use the pattern: "When you
want to do X, you can call the [`ClassName#method`](link). method"
This is more helpful than a passive description. The reader learns
the class, the method name, and what it does in one sentence.

Right: "When you talk to send a message to the model, you can call
[`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk)."

Right: "When you want to cancel an active request or tool call, you can call the
[`LLM::Agent#cancel!`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#cancel!)
method."

Wrong: "Input is sent with `talk`."
Wrong: "The `cancel!` method aborts the request."

Flag any section that starts with a verb.

## Step 3: Check the phrasing

Flag these words and suggest replacements:

| Flag | Replace with |
|---|---|
| leverage | use |
| utilize | use |
| facilitate | let, help, or do |
| empower | let |
| robust | cut it |
| seamless | cut it |
| allows you to | lets you |
| enables you to | lets you |
| in order to | to |
| invoke | call |
| Behind the scenes| Under the hood |

## Step 4: Check the formatting

**No unicode dashes.** Rephrase to avoid them. Do not replace
with a hyphen. Split into two sentences, use a semicolon, or
restructure.

**No text after code blocks.** Prose comes before the code.
Nothing after the closing triple backticks except the next heading.

**No text after the last table.** Move orphaned text above the table.
Do not move text that belongs to the surrounding Notes section; tables
inside Notes (such as keyboard shortcut references) stay where they are.

**No exclamation marks.** The author does not use them.

**No emoji.**

**Lines at most 100 columns.** Code blocks are exempt. Long lines
with API doc URLs can be wrapped at a natural break.

**API doc links.** Every first mention of an llm.rb class links to
r.uby.dev/api-docs.

## Step 5: Check method references

Every backtick-wrapped reference to an llm.rb class or method
in prose must use the full `ClassName#method` or `ClassName`
format with an API doc link. No bare backtick references to
llm.rb types outside code blocks.

Right: "Call [`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk) to send input to the model."

Right: "The built-in tracers include [`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html)."

Wrong: "Call `ctx.talk` to send input to the model."

Wrong: "You send input with `talk`."

Wrong: "The built-in tracers include `LLM::Tracer::Logger`."

Code blocks are exempt — inside code, `ctx.talk` is fine.

## Step 6: Check paragraph rhythm

Intro paragraphs should be 4 to 5 lines. A single sentence here
and there is fine. Paragraphs should not consistently run longer
than 5 lines without a break.

## Step 7: Know what to leave alone

These are the author's voice. Do not flag them:

- Short paragraphs. One sentence is fine.
- "lets" as a verb. Leave it alone.
- Honest trade offs. "A bit awkward" is the author.
- Self deprecation. "Could be improved" is the author.
- "ie" not "i.e.". "too" at end of sentences.
- Passive voice where the topic is the subject.

## Process

1. Read the index at `docs/deepdive.md` to see the file map.
2. Read each topic file under `docs/deepdive/`.
3. Work through each step above, in order.
4. Write findings to `research/scribe/style.md`. Only include
   sections with issues. Do not copy the entire deepdive.
