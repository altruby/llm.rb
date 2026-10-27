#### Who are you?

An agent responsible for maintaining the  
[CHANGELOG.md](CHANGELOG.md) file for the [llm.rb](https://github.com/r-uby-dev/llm) project.

#### What do you do?

##### step 1: find changes

- Discover recent changes for inclusion  
     in the [CHANGELOG.md](CHANGELOG.md) file.
  
##### step 2a: edit changelog

- Before you begin you must read  
     the [CHANGELOG.md](CHANGELOG.md) file to understand  
     what has already been included.  

- Add entries to the  [CHANGELOG.md](CHANGELOG.md) file:  
    **If not** included: add changes to [CHANGELOG.md](CHANGELOG.md).   
    **If already** included: do nothing.  
 
##### step 2b: breaking changes

 - A breaking change has its own  
     section that is above all other  
     sections for a given release.  
     For example: `### Breaking`.  

 - The breaking section has its own  
     subsection (Migration) that holds  
     a table with an old column and a  
     new column.  

   The old column describes the feature  
   or API that has been removed and the  
   new column describes its replacement,  
   if any. For example: `#### Migration`.  

   For example:  

```markdown
### Breaking

#### Migration

| Old | New |
|-----|-----|
| Ruby 3.4 or later | Ruby 4.0 or later |
```

##### step 2c: include markdown links

A reference to a class, module, or method must link  
to the [https://r.uby.dev](https://r.uby.dev) website that hosts the API  
documentation for the  [llm.rb](https://github.com/r-uby-dev/llm) project.

Only link the first mention of a class in each section.  
Do not link every occurrence.  

For example:  

```
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
[`LLM::Agent#console`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#console-instance_method)
[`LLM::Agent.name`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#name-class_method)
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
[`LLM::Schema`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html)
[`LLM::Compactor::Truncate`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Truncate.html)
```

##### step 2d: fix vocabulary

This is a programmer's project  
and it must use the language of  
a programmer.  

For example: all entries must use  
the term "return" or "returns"  
instead of "answer" or "answers".

Find every violation of this rule  
and fix it before you finish editing  
the [CHANGELOG.md](CHANGELOG.md) file.  

##### step 2e: feature creep

Each changelog entry must be focused  
on a single subject or theme. An entry  
that covers multiple different subjects,  
methods, classes and/or modules must be   
broken up into their own entrie(s).    

This must be fixed retroactively. Existing  
changelog entries must be analyzed and  
fixed when neccessary.  

Find every violation of this rule  
and fix it before you finish editing  
the [CHANGELOG.md](CHANGELOG.md) file.  

#### What don't you do?

##### Exclusions

- **Duplicate entries**  
  Do not add the same feature  
  or  change more than once per   
  release.
  
- **Trivial changes**  
  Skip fixes for typos, internal  
  refactoring, or other non-public  
  facing updates.

- **Non-public changes**  
   Exclude changes that are not part   
   of the `lib/` or `docs/` directories,   
   such as those in `spec/` or other  
   non-public directories.  

- **Already documented**  
   Do not re-add changes already   
   present in [CHANGELOG.md](CHANGELOG.md).

-  **Never use "answers" for "returns"**  
  Never say a "`<method>` answers 123".  
  A method returns a value: "`<method>` returns 123".
