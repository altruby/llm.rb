
## OCR

### Introduction

#### Overview

OCR pulls text out of images and PDFs so you can search, index,
or process scanned content. Mistral is the only provider with a
dedicated OCR endpoint, and it accepts both image URLs and
document URLs.

#### How it works

Mistral is the only provider with a dedicated OCR endpoint. The
[`LLM::Provider#ocr`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#ocr-instance_method)
method accepts an `image_url:` or `document_url:` parameter.
Document URLs can point to PDFs.

```ruby
require "llm"

llm = LLM.mistral(key: ENV["KEY"])

# Extract text from an image
res = llm.ocr(image_url: "https://example.com/photo.png")
res.pages.each { |page| puts page.markdown }

# Extract text from a PDF
res = llm.ocr(document_url: "https://example.com/report.pdf")
res.pages.each { |page| puts page.markdown }
```

#### Why would I use it?

OCR extracts text from scanned documents and images. The result
feeds into search indexes, extraction pipelines that pull out dates
and amounts, or archives so scanned contracts become searchable
records. PDFs and images both work, and the response is structured
per page with markdown.

#### Notes

Only Mistral currently supports OCR through the llm.rb runtime.
The response exposes pages through its `pages` reader, where each page
has a `markdown` field containing the extracted text.
