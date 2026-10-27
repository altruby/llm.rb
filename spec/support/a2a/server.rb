#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "socket"

module LLM
  ##
  # A stub A2A agent for the ractor specs. It serves an agent card,
  # answers `SendMessage` over the REST binding, and answers the same
  # message over the JSON-RPC binding.
  module A2AServer
    CARD = {
      "name" => "Hello World Agent",
      "description" => "Just a hello world agent",
      "version" => "0.0.1",
      "skills" => [
        {
          "id" => "hello_world",
          "name" => "Returns hello world",
          "description" => "just returns hello world"
        }
      ]
    }.freeze

    TASK = {
      "task" => {
        "id" => "task_1",
        "status" => {"state" => "TASK_STATE_COMPLETED"},
        "artifacts" => [
          {"parts" => [{"text" => "Hello, World!"}]}
        ]
      }
    }.freeze

    ##
    # The JSON-RPC binding names the method in the envelope, while the REST
    # binding posts the message payload itself - so a body that carries a
    # "message" is a SendMessage even though it has no "method" key.
    #
    # @param [Hash, nil] body
    # @return [Hash]
    def self.result(body)
      called = body && (body["method"] || (body["message"] && "SendMessage"))
      case called
      when "SendMessage" then TASK
      else {error: {code: -32601, message: "unknown method"}}
      end
    end

    ##
    # @param [String] method
    # @param [String] path
    # @param [Hash, nil] body
    # @return [Hash]
    def self.reply(method, path, body)
      case [method, path]
      when ["GET", "/.well-known/agent-card.json"]
        CARD
      when ["POST", "/message:send"]
        result(body)
      when ["POST", "/"]
        {"jsonrpc" => "2.0", "id" => body && body["id"], "result" => result(body)}
      else
        raise KeyError, "#{method} #{path}"
      end
    end

    ##
    # @param [TCPSocket] sock
    # @return [void]
    def self.handle(sock)
      method, path, _ = sock.gets.to_s.split(" ")
      headers = {}
      while (line = sock.gets) && line != "\r\n"
        key, value = line.split(": ", 2)
        headers[key.to_s.downcase] = value.to_s.chomp
      end
      raw = sock.read(headers["content-length"].to_i)
      body = raw.to_s.empty? ? nil : JSON.parse(raw)
      payload = begin
        JSON.generate(reply(method, path, body))
      rescue KeyError => ex
        JSON.generate("error" => ex.message)
      end
      sock.print(
        "HTTP/1.1 200 OK\r\n" \
        "Content-Type: application/json\r\n" \
        "Content-Length: #{payload.bytesize}\r\n" \
        "Connection: close\r\n\r\n" \
        "#{payload}"
      )
    ensure
      sock.close
    end

    ##
    # @param [Integer] port
    # @return [void]
    def self.http(port)
      server = TCPServer.new("127.0.0.1", port)
      loop do
        Thread.new(server.accept) { handle(_1) }
      end
    end
  end
end

if $0 == __FILE__
  LLM::A2AServer.http(Integer(ARGV[0]))
end
