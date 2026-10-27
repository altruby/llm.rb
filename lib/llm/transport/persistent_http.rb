# frozen_string_literal: true

class LLM::Transport
  ##
  # The {LLM::Transport::PersistentHTTP LLM::Transport::PersistentHTTP}
  # transport is the built-in adapter for
  # [Net::HTTP::Persistent](https://github.com/drbrain/net-http-persistent).
  # It manages pooled HTTP connections, tracks active requests by owner,
  # and interrupts in-flight requests when needed.
  #
  # @api private
  class PersistentHTTP < self
    include NetHTTPAdapter

    INTERRUPT_ERRORS = [::IOError, ::EOFError, Errno::EBADF].freeze
    ActiveRequest = Struct.new(:client, :connection, keyword_init: true)

    ##
    # @param [String] host
    # @param [Integer] port
    # @param [Integer] timeout
    # @param [Integer] connect_timeout
    # @param [Boolean] ssl
    # @return [LLM::Transport::PersistentHTTP]
    def initialize(host:, port:, timeout:, connect_timeout:, ssl:)
      @host = host
      @port = port
      @timeout = timeout
      @connect_timeout = connect_timeout
      @ssl = ssl
      @base_uri = URI("#{ssl ? "https" : "http"}://#{host}:#{port}/")
      @monitor = Monitor.new
    end

    ##
    # Returns the current request owner.
    # @return [Object]
    def request_owner
      return Fiber.current unless defined?(::Async)
      Async::Task.current? ? Async::Task.current : Fiber.current
    end

    ##
    # @return [Array<Class<Exception>>]
    def interrupt_errors
      [*INTERRUPT_ERRORS, *optional_interrupt_errors]
    end

    ##
    # Interrupt an active request, if any.
    # @param [Fiber, Async::Task] owner
    # @return [nil]
    def interrupt!(owner)
      req = request_for(owner) or return
      lock { (@interrupts ||= {})[owner] = true }
      close_socket(req.connection&.http)
      req.client.finish(req.connection)
      owner.stop if owner.respond_to?(:stop)
    rescue *interrupt_errors
      nil
    end

    ##
    # Returns whether an execution owner was interrupted.
    # @param [Fiber] owner
    # @return [Boolean, nil]
    def interrupted?(owner)
      lock { @interrupts&.delete(owner) }
    end

    ##
    # Performs a request on the current HTTP
    # transport. Accepts both `Net::HTTPRequest`
    # and {LLM::Transport::Request}.
    #
    # @param [Net::HTTPRequest, LLM::Transport::Request] request
    # @param [Fiber] owner
    # @param [LLM::Object, nil] stream
    # @yieldparam [LLM::Transport::Response] response
    # @return [Object]
    def request(request, owner:, stream: nil, &b)
      req = resolve_request(request)
      uri = URI.join(base_uri, req.path)
      client.connection_for(uri) do |connection|
        set_request(ActiveRequest.new(client:, connection:), owner)
        perform_request(connection.http, req, stream, &b)
      end
    ensure
      clear_request(owner)
    end

    private

    ##
    # @api private
    attr_reader :host,
                :port,
                :timeout,
                :connect_timeout,
                :ssl,
                :base_uri

    ##
    #  Returns the client
    # @return [Net::HTTP::Persistent]
    def client
      lock { @client ||= build_client }
    end

    ##
    # @return [Net::HTTP::Persistent]
    def build_client
      LLM.require "net/http/persistent" unless defined?(Net::HTTP::Persistent)
      client = Net::HTTP::Persistent.new(name: self.class.name)
      client.read_timeout = timeout
      client.open_timeout = connect_timeout
      client
    end

    ##
    # @api private
    # @return[void]
    def close_socket(http)
      socket = http&.instance_variable_get(:@socket) or return
      socket = socket.io if socket.respond_to?(:io)
      socket.close
    rescue *interrupt_errors
      nil
    end

    ##
    # @api private
    def request_for(owner)
      lock do
        @requests ||= {}
        @requests[owner]
      end
    end

    ##
    # @api private
    def set_request(req, owner)
      lock do
        @requests ||= {}
        @requests[owner] = req
      end
    end

    ##
    # @api private
    def clear_request(owner)
      lock { @requests&.delete(owner) }
    end

    ##
    # @api private
    def lock(&)
      @monitor.synchronize(&)
    end

    ##
    # @api private
    def optional_interrupt_errors
      defined?(::Async::Stop) ? [Async::Stop] : []
    end
  end
end
