
## Schema

### Introduction

#### Overview

A schema describes the shape of a structured response you expect
from the model. Instead of parsing free-form text, you declare
the expected structure and the runtime coerces the response into
an object with typed accessors.

#### How it works

When you want a structured response from the model, subclass
[`LLM::Schema`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html)
and declare properties with types and constraints. When you pass
the schema to
[`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk)
or
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk),
the runtime includes it in the request parameters. The provider returns a
JSON object matching the schema, which is coerced into an
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html) with typed accessors.

```ruby
class Estimation < LLM::Schema
  property :age, Integer, "The estimated age of the person"
  property :confidence, Number, "Your confidence in the estimate"
  property :applicable, Boolean, "True when the photo contains a person"
  property :comments, String, "Any additional comments"
  required %i[age confidence applicable comments]
end

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, schema: Estimation)
res = agent.ask "Given this photo, provide an age estimate", with: "photo.jpg"

estimate = res.content!

if estimate.applicable
  print "The person is approx ", estimate.age.to_s, " years old"
else
  print "This photo is not applicable: ", estimate.comments
end
```

#### Why would I use it?

Schemas give you structured data instead of free text. Pass the
result to other code without parsing. Use them for classification,
extraction, or any workflow where the output needs to feed into
another system.

#### Notes

Schemas can define objects, arrays, enums, and nested schemas.
They are also used internally by
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
for parameter definitions, so you already benefit from them
when you declare tool parameters.

### Types

#### Overview

A schema is built from a small set of types: the JSON primitives, an
array of a type, an enum of allowed values, a nested schema, and the
combinators `any_of`, `all_of`, and `one_of`. Every type takes a
description, and any type can be marked required or given a default.

#### How it works

A property is declared with its type and description. `String`,
`Integer`, `Number`, and `Boolean` are the primitives, `Array[Type]`
wraps one, and `Enum[...]` constrains a value to a fixed set. A nested
schema is just another `LLM::Schema` subclass used as the type:

```ruby
class Address < LLM::Schema
  property :street, String, "Street address"
  required %i[street]
end

class Person < LLM::Schema
  property :name, String, "Person's name"
  property :age, Integer, "Person's age"
  property :hobbies, Array[String], "Person's hobbies"
  property :address, Address, "Person's address"
  required %i[name age hobbies address]
end
```

`Array[String, Integer]` declares an array whose items may be either
type. Options on `property` set a leaf directly, so
`property :age, Integer, "Person's age", required: true` marks one
property required, and
[`LLM::Schema.defaults`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html#defaults-class_method)
sets defaults for several at once:

```ruby
class Search < LLM::Schema
  property :query, String, "The search query"
  property :limit, Integer, "The number of results"
  required %i[query]
  defaults limit: 10
end
```

The same schema can be built without a class, using the value methods:

```ruby
schema = LLM::Schema.new
schema.object(
  name: schema.string.required,
  age: schema.integer.required,
  colors: schema.array(schema.string.enum("red", "green")).required
)
```

#### Why would I use it?

Types tell the model what shape to produce. A plain `String` is the
loosest, an `Enum` the tightest, and a nested schema lets a structured
response contain a structured value. Because the same machinery backs
tool parameters, anything you learn here applies to tools too.

#### Notes

`any_of`, `all_of`, and `one_of` combine types, and
[`LLM::Schema.to_s`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html#to_s-class_method)
renders the schema as a prompt-friendly string. `required` and
`defaults` refer to properties that already exist, so declare the
property first and mark it afterwards.

### Parsing

#### Overview

[`LLM::Schema.parse`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html#parse-class_method)
turns an external JSON Schema, such as one a tool manifest or a
provider hands you, into the same leaf objects the Ruby DSL produces,
so a schema written elsewhere can be used here.

#### How it works

Pass a Hash (or an `LLM::Object`) and get a leaf back. Object, array,
string, integer, number, boolean, and null types are supported, along
with `$ref` references into the same document, the `anyOf`, `oneOf`,
and `allOf` unions, and the metadata keywords `description`, `default`,
`enum`, and `const`. The range keywords `minLength`/`maxLength` and
`minimum`/`maximum`/`multipleOf` are applied to the leaf as well:

```ruby
schema = LLM::Schema.parse(
  "type" => "object",
  "properties" => {
    "name" => {"type" => "string", "minLength" => 1},
    "age"  => {"type" => "integer", "minimum" => 0, "maximum" => 120}
  },
  "required" => ["name"]
)

puts schema
# object
#   name: string (required, minLength: 1)
#   age?: integer (minimum: 0, maximum: 120)
```

#### Why would I use it?

A JSON Schema you already have can drive a structured response without
being rewritten by hand. Parsing produces the same objects the Ruby
DSL builds, so the result is used the same way.

#### Notes

An unsupported `type`, an unresolvable `$ref`, or a `$ref` that does
not start with `#/` raises `TypeError`. When a schema omits `type`,
the parser infers it from `const`, `enum`, or `default`.
