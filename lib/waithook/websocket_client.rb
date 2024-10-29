require 'socket'
require 'websocket'
require 'stringio'

require_relative 'logger_with_trace'

class Waithook
  # Simple websocket client, internally use websocket gem to construct and parse websocket messages
  #
  # Usage:
  #
  #   client = WebsocketClient.new(host: HOST, port: PORT, path: 'test-ruby')
  #   client.send_ping!
  #   client.send_message!("Hello, server")
  #   type, data = client.wait_message # => type == :text, data is message content as a string
  #
  class WebsocketClient

    attr_accessor :logger

    # Waiter object, blocking current thread. Better abstraction for ruby's Queue utility class
    #
    #   message_waiter = Waiter.new
    #   Thread.new { sleep 5; message_waiter.notify('Done!!!') }
    #   message_waiter.wait # => return 'Done!!!' after 5 seconds pause
    #
    class Waiter
      # Waiting for someone to call #notify
      def wait
        @queue = Queue.new
        @queue.pop(false)
      end

      # Notify waiting side
      def notify(data)
        @queue.push(data)
      end
    end

    # Available options:
    # * :host - hostname
    # * :port - server port (default 80)
    # * :path - HTTP path
    # * :ssl  - true/false (will detect base on port if blank)
    # * :ssl_version
    # * :verify_mode
    # * :logger_level - logger level, default :info
    # * :output - output stream for default logger. If value == false then it will be silent, default is $stdout
    # * :logger - custom logger object
    def initialize(options = {})
      # required: :host, :path

      @host = options[:host]
      @port = options[:port] || 80
      @path = options[:path]

      @use_ssl = options.has_key?(:ssl) ? options[:ssl] : @port == 443
      @options = options

      @waiters = []
      @connect_waiters = []
      @handshake_received = false
      @messages = Queue.new
      @is_open = false

      @output = options[:output] || $stdout

      if options[:logger] === false
        @output = StringIO.new
      end

      if options[:logger] && options[:logger] != true
        @logger = options[:logger]
      else
        @logger = LoggerWithTrace.new(@output).setup(
          progname: self.class.name,
          level: options[:logger_level] || :info
        )
      end
    end

    # Establish connection to server and send initial handshake
    def connect!
      logger.info "Connecting to #{@host} #{@port}"

      tcp_socket = TCPSocket.open(@host, @port)

      if @use_ssl
        require 'openssl'
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = @options[:ssl_version] if @options[:ssl_version]
        ctx.verify_mode = @options[:verify_mode] if @options[:verify_mode]
        cert_store = OpenSSL::X509::Store.new
        cert_store.set_default_paths
        ctx.cert_store = cert_store
        @socket = ::OpenSSL::SSL::SSLSocket.new(tcp_socket, ctx)
        @socket.connect
      else
        @socket = tcp_socket
      end

      @is_open = true
      @handshake = WebSocket::Handshake::Client.new(url: "ws://#{@host}/#{@path.to_s.sub(/^\//, '')}")

      logger.trace "Sending handshake:\n#{@handshake}"

      @socket.print(@handshake)
      _start_parser!

      self
    end

    # Return true/false
    def connected?
      !!@is_open
    end

    def _start_parser!
      @reader, @writter = IO.pipe
      @processing_thread = Thread.new do
        # Thread.current.abort_on_exception = true
        begin
          logger.debug "Start reading in thread"
          handshake_response = _wait_handshake_response
          @handshake << handshake_response
          logger.trace "Handshake received:\n #{handshake_response}"

          @frame_parser = WebSocket::Frame::Incoming::Client.new
          _handshake_recieved!
          _wait_frames!
        rescue Object => error
          # if got error - close socket and end thread
          # @last_connection_error will be detected in #wait_message and raised to caller thread,
          # so caller can decide to reconnect or do something else
          @last_connection_error = error
          close!(send_close: false, kill_processing_thread: false) rescue nil
          @messages.close

          logger.error "#{error.class}: #{error.message}\n#{error.backtrace.join("\n")}"
        end
      end
    end

    # Send <tt>:ping</tt> message to server
    def send_ping!
      _send_frame(:ping)
    end

    # Send <tt>:pong</tt> message to server, usually as a response to :ping message
    def send_pong!
      _send_frame(:pong)
    end

    # Send message to server (type <tt>:text</tt>)
    def send_message!(payload)
      _send_frame(:text, payload)
    end

    # Wait for new message (thread safe, all waiting threads will receive a message)
    # Message format [type, data], e.g. <tt>[:text, "hello world"]</tt>
    def wait_new_message
      waiter = Waiter.new
      @waiters << waiter
      waiter.wait
    end

    # Synchronously waiting for new message. Not thread safe, only one thread will receive message
    # Message format [type, data], e.g. <tt>[:text, "hello world"]</tt>
    def wait_message
      begin
        message = @messages.pop
        if (!message || message.first == nil) && @messages.closed? && @last_connection_error
          raise @last_connection_error
        end

        return message
      rescue => error
        if @last_connection_error
          raise @last_connection_error
        else
          raise error
        end
      end
    end

    # Wait until server handshake recieved.
    # Once it's received - we can are listening for new messages
    # and connection is ready for sending data
    def wait_handshake!
      return true if @handshake_received
      waiter = Waiter.new
      @connect_waiters << waiter
      waiter.wait
      self
    end
    alias_method :wait_connected, :wait_handshake!

    def _handshake_recieved!
      @handshake_received = true
      while waiter = @connect_waiters.shift
        waiter.notify(true)
      end
    end

    def _notify_waiters(type, payload)
      while waiter = @waiters.shift
        waiter.notify([type, payload])
      end
    end

    def _send_frame(type, payload = nil)
      wait_handshake!
      frame = WebSocket::Frame::Outgoing::Client.new(version: @handshake.version, data: payload, type: type)
      logger.trace "Sending :#{frame.type} #{payload ? "DATA: #{frame.data}" : "(no data)"}"
      @socket.write(frame.to_s)
    end

    def _process_frame(message)
      logger.trace "Received :#{message.type} #{message.data ? "DATA: #{message.data}" : "(no data)"}"

      if message.type == :pong
        logger.debug "Got pong"
      end

      if message.type == :ping
        send_pong!
      end
      if message.type == :text
        @messages.push([message.type, message.data])
        _notify_waiters(message.type, message.data)
      end
    end

    def ping_sender(interval = 60)
      while @is_open
        send_ping!
        sleep interval
      end
    end

    def _wait_frames!
      while char = @socket.getc
        @frame_parser << char
        while message = @frame_parser.next
          _process_frame(message)
        end
      end
    end

    def _wait_handshake_response
      logger.debug "Waiting handshake response"
      data = []
      while line = @socket.gets
        data << line
        if line == "\r\n"
          break
        end
      end
      data.join("")
    end

    def socket_open?
      @socket && !@socket.closed?
    end

    # Send <tt>:close</tt> message to socket and close socket connection
    def close!(send_close: true, kill_processing_thread: true)
      unless @is_open
        logger.info "Already closed"
        return false
      end

      logger.info "Disconnecting from #{@host} #{@port}"
      @processing_thread.kill if kill_processing_thread
      _send_frame(:close) if send_close
      @socket.close
      @is_open = false

      return true
    end
  end
end
