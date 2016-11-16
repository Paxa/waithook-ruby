require 'socket'
require 'websocket'
require 'looksee'

hostname = 'waithook.herokuapp.com'
port = 80

class WebsocketClient

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
    # required: :host, :port, :path
    options.merge({
      ssl: false
    })
    @host = options[:host]
    @port = options[:port] || 80
    @path = options[:path]
    @waiters = []
    @messages = Queue.new
  end

  def connect!
    puts "Connecting to #{@host} #{@port}"
    @socket = TCPSocket.open(@host, @port)
    @handshake = WebSocket::Handshake::Client.new(url: "ws://#{@host}/#{@path}")
    puts "Sending:\n#{@handshake}"
    @socket.print(@handshake)
    _start_parser!
  end

  def _start_parser!
    @reader, @writter = IO.pipe
    @processing_thread = Thread.new do
      Thread.current.abort_on_exception = true
      begin
        puts "Start reading in thread"
        @handshake << _wait_handshake_response
        puts "Handshake received, version: #{@handshake.version}"
        @frame_parser = WebSocket::Frame::Incoming::Client.new
        _wait_frames!
      rescue => error
        puts "#{error.class}: #{error.message}\n#{error.backtrace.join("\n")}"
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
      p waiter
      waiter.notify([type, payload])
    end
  end

  def _send_frame(type, payload = nil)
    frame = WebSocket::Frame::Outgoing::Client.new(version: @handshake.version, data: payload, type: type)
    puts "Sending #{frame.type} -- #{frame.data}"
    @socket.write(frame.to_s)
  end

  def _process_frame(message)
    puts "Frame (#{message.type}): #{message}"
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
    puts "Waiting handshake response"
    data = []
    while line = @socket.gets
      data << line
      if line == "\r\n"
        puts "Done!"
        break
      end
    end
    data.join("")
  end

  def close!
    puts "Closing"
    @processing_thread.kill
    @socket.close
  end
end

HOST = 'localhost'
PORT = 3012
#HOST = 'waithook.herokuapp.com'
#PORT = 80

client = WebsocketClient.new(host: HOST, port: PORT, path: 'test-ruby')

client.connect!

#while true
  sleep 3
  require 'open-uri'
  open("http://#{HOST}:#{PORT}/test-ruby")
  type, data = client.wait_message
  p [type, data]
  client.close!
#end

#socket = TCPSocket.open(hostname, port)
#
#request = WebSocket::Handshake::Client.new(url: 'ws://waithook.herokuapp.com/test-ruby')
#puts request
#
#socket.print(request)
#
#while line = socket.gets
#  puts line.chop
#end
#
#socket.close
