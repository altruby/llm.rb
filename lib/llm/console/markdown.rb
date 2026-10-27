# frozen_string_literal: true

class LLM::Console
  ##
  # This class is designed to represent a markdown
  # string (typically from a model's response) as a
  # tree of objects where each object contains a piece
  # of text, and also optional style information for
  # that text (eg bold, underscore, ...)
  class Markdown
    require_relative "markdown/table"
    require_relative "markdown/parser"
    include Table

    ##
    # @param [String] text
    # @param [Integer] width
    # @return [LLM::Console::Markdown]
    def initialize(text, width)
      ##
      # 'Parser' treats HTML, smart quotes,
      # and typographic symbols as literal
      # text, so the original input comes
      # through unchanged.
      options = {input: Parser}
      @doc = Kramdown::Document.new(fenced_code_blocks([*text].flatten.join("\n")), options)
      @width = width
      @ast = []
    end

    ##
    # @return [Array<Node>]
    def ast
      @ast.tap do
        ##
        # Recursively travels the markdown document and
        # populates the `@ast` variable along the way.
        # The AST is composed of structured data that
        # carries both text and styling information that
        # is applied by the UI thread.
        walk(@doc.root)

        ##
        # This is required because the AST collects
        # empty nodes towards the end of the tree.
        # If we don't pop them we end up with excessive
        # amount of newlines between turns.
        last = @ast.last
        while last and last[:text].to_s.strip.empty?
          @ast.pop
          last = @ast.last
        end
      end
    end

    private

    ##
    # Recursively walk from the head node to the
    # tail node. This method mutates the `@ast`
    # variable. A future refactor might be worthwhile
    # since this method is implemented with side effects,
    # but it probably could return the ast instead.
    def walk(node, attrs = nil)
      case node.type
      when :root
        node.children.each { walk(_1, attrs) }
      when :text
        emit(node.value.to_s, attrs)
      when :p
        node.children.each { walk(_1, attrs) }
        emit("\n\n", attrs)
      when :header
        emit("\n", attrs)
        node.children.each { walk(_1, Curses::A_BOLD | Color.white) }
        emit("\n", attrs)
      when :strong
        node.children.each { walk(_1, Curses::A_BOLD | Color.white) }
      when :em
        node.children.each { walk(_1, Curses::A_UNDERLINE) }
      when :codespan
        emit(node.value, Color.green)
      when :codeblock
        emit("#{lang(node)}\n", Curses::A_BOLD | Color.white) unless lang(node).empty?
        emit(node.value, Color.green)
        emit("\n\n", attrs)
      when :entity
        emit(node.value.char, attrs)
      when :br
        emit("\n", attrs)
      when :ul, :ol
        node.children.each { walk(_1, attrs) }
      when :li
        node.children.each { walk(_1, attrs) }
      when :table
        walk_table(node, attrs)
      when :thead, :tbody
        node.children.each { walk(_1, attrs) }
      when :tr
        emit("| ", attrs)
        node.children.each { walk(_1, attrs) }
        emit("\n", attrs)
      when :td, :th
        node.children.each { walk(_1, attrs) }
        emit(" | ", attrs)
      when :blockquote
        emit("> ", attrs)
        node.children.each { walk(_1, attrs) }
      when :hr
        emit("─" * @width, attrs)
        emit("\n\n", attrs)
      when :a
        node.children.each { walk(_1, Curses::A_UNDERLINE | Color.green) }
      when :img
        emit("[image: #{node.attr["alt"]}]", attrs)
      else
        node.children.each { walk(_1, attrs) }
      end
    end

    def emit(text, attrs)
      @ast.push(Node.new(text.to_s, attrs))
    end

    ##
    # Kramdown's native fenced-code syntax uses
    # `~~~`, not the GitHub-style ``` fences that
    # models commonly emit. Rewrite ```lang blocks
    # so they are parsed as real code blocks instead
    # of inline code spans. The language is preserved
    # so Kramdown tags the block with a `language-*`
    # class.
    # @param [String] text
    # @return [String]
    def fenced_code_blocks(text)
      text.gsub(/^```(\S*)\s*$/) { "~~~#{$1}" }
    end

    ##
    # Extracts the language from a code block's
    # `language-*` class.
    # @param [Kramdown::Element] node
    # @return [String]
    def lang(node)
      node.attr["class"].to_s.sub(/\Alanguage-/, "")
    end
  end
end
