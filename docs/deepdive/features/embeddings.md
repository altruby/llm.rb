
## Embeddings

### Introduction

#### Overview

Embeddings convert text into numerical vectors that capture semantic
meaning. Similar texts produce vectors that are close together in the
vector space, enabling semantic search, clustering, and classification.
Most providers offer embedding models through an
[`LLM::Provider#embed`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#embed)
method.

llm.rb also includes support for OpenAI's vector store API, which
provides a managed vector database as an HTTP service.

#### How it works

When you want to generate an embedding vector for a piece of text,
call
[`LLM::Provider#embed`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#embed)
on any provider that supports it. The method accepts an input string
or array of strings and returns a response with the resulting
embeddings, which can be stored in a vector database and used for
similarity search at query time:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
body = "llm.rb is Ruby's capable AI runtime."
embedding = llm.embed([body]).embeddings.first
```

#### Why would I use it?

Embeddings are the foundation for Retrieval-Augmented Generation (RAG).
Store embeddings for your documents, then retrieve the most relevant
chunks at query time and feed them into the model as context. This
pattern is one of the most common AI workflows.

#### Notes

Not all providers support embeddings. The following providers have an
`embed` method of their own:

- OpenAI (`text-embedding-3-small`)
- DeepInfra (`BAAI/bge-m3`)
- Ollama (`qwen3:latest`)
- Google (`gemini-embedding-2`)
- Mistral (`mistral-embed`)
- OpenRouter (`openai/text-embedding-3-small`)
- Bedrock (the model is given per call)

The providers built on OpenAI inherit its `embed`, so DeepSeek, xAI,
Z.ai, Moonshot, Alibaba, and llama.cpp answer it too, against their own
OpenAI-compatible endpoint. Anthropic is the exception: it defines no
`embed`, so the call raises `NotImplementedError`.

### Vector stores (OpenAI)

#### Overview

OpenAI's vector store API provides a managed vector database as an
HTTP service. You upload files, add them to a vector store, and
search across them. The runtime handles chunking, embedding, and
indexing on OpenAI's side.

#### How it works

When you want to create a vector store, upload files, and search
across them, you can call methods on
[`LLM::OpenAI::VectorStores`](https://r.uby.dev/api-docs/llm.rb/LLM/OpenAI/VectorStores.html).
Upload files first, then create the store with
[`LLM::OpenAI::VectorStores#create_and_poll`](https://r.uby.dev/api-docs/llm.rb/LLM/OpenAI/VectorStores.html#create_and_poll-instance_method)
to
wait until indexing completes:

```ruby
llm = LLM.openai(key: ENV["KEY"])

# Upload files first
files = %w[report.pdf manual.pdf].map { |f| llm.files.create(file: f) }

# Create a vector store with the files and wait for indexing
store = llm.vector_stores.create_and_poll(
  name: "documents",
  file_ids: files.map(&:id)
)

# Search across the store
results = llm.vector_stores.search(
  vector: store,
  query: "What is the deadline?",
  max_results: 5
)
results.each do |chunk|
  text = chunk.content.map { |c| c.text }.join
  puts "[score=#{chunk.score}] #{text[0..120]}..."
end
```

#### Why would I use it?

OpenAI's vector store API removes the operational overhead of running
your own vector database. There is no infrastructure to manage, no
indexing pipeline to maintain, and no embedding model to configure.
The trade-off is vendor lock-in and per-request pricing.

#### Notes

Vector stores require the `openai` provider. Other providers such as
DeepInfra, Google, and Mistral expose an embedding method but no
vector store API. For a self-hosted vector database, pair
[`LLM::Provider#embed`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#embed)
with sqlite-vec or pgvector.

### Local vector search

#### Overview

Local vector search combines
[`LLM::Provider#embed`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#embed)
with a local vector database such as
[sqlite-vec](https://github.com/asg017/sqlite-vec) or
[pgvector](https://github.com/pgvector/pgvector). This approach keeps
your data on your own infrastructure.

#### How it works

When you want to store embeddings in a local database and search
them later, generate vectors with any provider, store the embedding
alongside the content, and query with a similarity search:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])

# Store: embed text and save it with a vector column
body = "llm.rb is Ruby's capable AI runtime."
embedding = llm.embed([body]).embeddings.first
Document.create!(title: "llm.rb", body:, embedding:)

# Query: embed the question and find similar documents
query = "What is llm.rb?"
query_embedding = llm.embed([query]).embeddings.first
results = Document.order(Arel.sql("embedding <=> ?", query_embedding)).limit(5)
```

#### Why would I use it?

Local vector search gives you full control over your data, no
per-query costs beyond your embedding provider, and the ability
to use any LLM provider for the generation step. It pairs well
with local providers like Ollama for a fully self-hosted stack.

#### Notes

The exact query syntax depends on your vector database. sqlite-vec
uses `vec_distance_L2` for Euclidean distance, while pgvector uses
the `<=>` operator for cosine distance. Check your database
documentation for the correct similarity function.
