require 'socket'
require 'logger'
require 'websocket'

class WebsocketClient

  attr_accessor :logger

  class Waiter
    def wait
      @queue = Queue.new
      @queue.pop(false)
    end

    def notify(data)
      @queue.push(data)
    end
  end

  def initialize(options = {})
    # required: :host, :path

    @host = options[:host]
    @port = options[:port] || 80
    @path = options[:path]

    @use_ssl = options.has_key?(:ssl) ? options[:ssl] : @port == 443
    @options = options

    @waiters = []
    @handshake_received = false
    @messages = Queue.new
    @is_open = false

    @output = options[:output] || STDOUT

    if options[:logger]
      @logger = options[:logger]
    else
      @logger = Logger.new(@output)
      @logger.progname = self.class.name
      @logger.formatter = proc do |serverity, time, progname, msg|
        msg.lines.map do |line|
          "#{progname} :: #{line}"
        end.join("") + "\n"
      end
    end
  end

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
    @handshake = WebSocket::Handshake::Client.new(url: "ws://#{@host}/#{@path}")

    logger.debug "Sending handshake:\n#{@handshake}"

    @socket.print(@handshake)
    _start_parser!

    self
  end

  def connected?
    !!@is_open
  end

  def _start_parser!
    @reader, @writter = IO.pipe
    @processing_thread = Thread.new do
      Thread.current.abort_on_exception = true
      begin
        logger.debug "Start reading in thread"
        handshake_response = _wait_handshake_response
        @handshake << handshake_response
        logger.debug "Handshake received:\n #{handshake_response}"

        @frame_parser = WebSocket::Frame::Incoming::Client.new
        @handshake_received = true
        _wait_frames!
      rescue Object => error
        logger.error "#{error.class}: #{error.message}\n#{error.backtrace.join("\n")}"
        raise error
      end
    end
  end

  def send_ping!
    _send_frame(:ping)
  end

  def send_pong!
    _send_frame(:pong)
  end

  def send_message!(payload)
    _send_frame(:text, payload)
  end

  def wait_handshake!
    while !@handshake_received
      sleep 0.001
    end
    self
  end

  def wait_new_message
    waiter = Waiter.new
    @waiters << waiter
    waiter.wait
  end

  def wait_message
    @messages.pop
  end

  def _notify_waiters(type, payload)
    while waiter = @waiters.shift
      waiter.notify([type, payload])
    end
  end

  def _send_frame(type, payload = nil)
    wait_handshake!
    frame = WebSocket::Frame::Outgoing::Client.new(version: @handshake.version, data: payload, type: type)
    logger.debug "Sending :#{frame.type} #{payload ? "DATA: #{frame.data}" : "(no data)"}"
    @socket.write(frame.to_s)
  end

  def _process_frame(message)
    if message.type == :ping
      send_pong!
    end
    if message.type == :text
      @messages.push([message.type, message.data])
      _notify_waiters(message.type, message.data)
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

  def close!(options = {send_close: true})
    unless @is_open
      logger.info "Already closed"
      return false
    end

    logger.info "Disconnecting from #{@host} #{@port}"
    @processing_thread.kill
    _send_frame(:close) if options[:send_close]
    @socket.close
    @is_open = false

    return true
  end
end
