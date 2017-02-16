require 'net/http'
require 'uri'
require 'timeout'
require 'json'
require 'stringio'

require_relative 'waithook/logger_with_trace'
require_relative 'waithook/websocket_client'
require_relative 'waithook/cli'

class Waithook

  # Default server host
  SERVER_HOST = "waithook.com"
  # Default server port
  SERVER_PORT = 80

  # Connect to server and start filter incoming messages (optionally)
  #
  # Usage:
  #   Waithook.default_path = 'my-notification-endpoint'
  #   waithook = Waithook.subscribe(timeout: 10) do |message|
  #     message.json_body['user_name'] == 'John Doe' # will return messages only passing this criteria
  #   end
  #   waithook.forward_to('http://localhost:4567/webhook', raise_on_timeout: true)
  #
  # <tt>options</tt> argument is will be passed to #initialize
  #
  def self.subscribe(options = {}, &block)
    instance = new(options)
    if block
      instance.filter = block
    end
    instance.connect! unless instance.started?
    instance
  end

  # Default path that it will be subscribed to
  def self.default_path=(value)
    @default_path = value
  end

  # Accessor for @default_path
  def self.default_path
    @default_path
  end

  # Filter (Proc), can be used to to filter incoming messages
  attr_accessor :filter
  # Array of all recieved messages
  attr_accessor :messages
  # Websocket client, instance of Waithook::WebsocketClient
  attr_reader :client
  # Connection options, hash
  attr_reader :options

  # Available options:
  # * :host
  # * :port
  # * :auto_connect - whenever connect to server automatically when instance is created (default is true)
  # * :path
  # * :timeout
  # * :logger_level - logger level, default :info
  # * :output - output stream for default logger. If value == false then it will be silent, default is $stdout
  # * :logger - custom logger object
  #
  def initialize(options = {})
    @options = {
      host: SERVER_HOST,
      port: SERVER_PORT,
      auto_connect: true,
      path: self.class.default_path
    }.merge(options)

    if @options[:path] == nil
      raise ArgumentError, ":path is missing. Please add :path to options argument or set Waithook.default_path = 'foo'"
    end

    # TODO: add SSL options
    @client = WebsocketClient.new(
      path: @options[:path],
      host: @options[:host],
      port: @options[:port],
      logger: @options[:logger],
      logger_level: @options[:logger_level],
      output: @options[:output]
    )

    @messages = []
    @filter = nil
    @started = false

    connect! if @options[:auto_connect]
  end

  # Logger object
  def logger
    @logger ||= LoggerWithTrace.new(@options[:logger] ? $stdout : StringIO.new).setup(
      progname: self.class.name,
      level: @options[:logger_level] || :info
    )
  end

  # Start connection to waithook server
  def connect!
    raise "Waithook connection already started" if @started
    @started = true
    @client.connect!.wait_handshake!
    self
  end

  # Whenever connected to server or not
  def started?
    !!@started
  end

  # Send all incoming webhook requests to running HTTP server
  #
  #   webhook = Waithook.subscribe(path: 'my-webhoooks').forward_to('http://localhost:3000/notification')
  #
  def forward_to(url, options = {})
    webhook = wait_message(options)
    webhook.send_to(url) unless webhook.nil?
  end

  # Wait incoming request information (wait message on websocket connection)
  def wait_message(options = {})
    raise_timeout_error = options.has_key?(:raise_on_timeout) ? options[:raise_on_timeout] : true
    timeout = options[:timeout] || @options[:timeout] || 0

    start_time = Time.new.to_f
    Timeout.timeout(timeout) do
      while true
        _, data = @client.wait_message
        webhook = Webhook.new(data)
        if @filter && @filter.call(webhook) || !@filter
          @messages << webhook
          return webhook
        end
      end
    end
  rescue Timeout::Error => error
    time_diff = (Time.now.to_f - start_time).round(3)
    logger.error "#{error.class}: #{error.message} (after #{time_diff} seconds)"
    raise error if raise_timeout_error
    return nil
  end

  # Close connection to server
  def close!
    @client.close!
    @started = false
  end

  # Represent incoming request to waithook,
  # that was send to client as JSON via websocket connection
  class Webhook
    # Original request URL, e.g. '/my-notification-endpoint?aaa=bbb'
    attr_reader :url
    # Hash of headers
    attr_reader :headers
    # Request body (for POST, PATCH, PUT)
    attr_reader :body
    # Request method ("GET", "POST", "PATCH", etc)
    attr_reader :method
    # Raw message from waithook server
    attr_reader :message

    def initialize(payload)
      @message = payload
      data = JSON.parse(@message)
      @url = data['url']
      @headers = data['headers']
      @body = data['body']
      @method = data['method']
    end

    # Returns Hash.
    # Access request body encoded as JSON (for POST, PATCH, PUT)
    def json_body
      if @body
        @json_body ||= JSON.parse(@body)
      end
    end

    # Send webhook information to other HTTP server
    #
    #   webhook = Waithook.subscribe(path: 'my-webhoooks').wait_message
    #   webhook.send_to('http://localhost:3000/notification')
    #
    def send_to(url)
      uri = URI.parse(url)
      response = nil

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http_klass = case method
          when "GET"    then Net::HTTP::Get
          when "POST"   then Net::HTTP::Post
          when "PUT"    then Net::HTTP::Put
          when "PATCH"  then Net::HTTP::Patch
          when "HEAD"   then Net::HTTP::Head
          when "DELETE" then Net::HTTP::Delete
          when "MOVE"   then Net::HTTP::Move
          when "COPY"   then Net::HTTP::Copy
          else Net::HTTP::Post
        end

        request = http_klass.new(uri)
        headers.each do |key, value|
          request[key] = value
        end

        if body
          request.body = body
        end

        response = http.request(request)
      end

      response
    end
  end
end
