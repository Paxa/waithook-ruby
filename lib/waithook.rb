require 'net/http'
require 'timeout'
require 'json'
require 'stringio'

require_relative 'waithook/logger_with_trace'
require_relative 'waithook/websocket_client'

class Waithook

  SERVER_HOST = "waithook.herokuapp.com"
  SERVER_PORT = 443

  def self.subscribe(options = {}, &block)
    instance = new(options)
    if block
      instance.filter = block
    end
    instance.connect! unless instance.started?
    instance
  end

  def self.default_path
    @default_path
  end
 
  def self.default_path=(value)
    @default_path = value
  end

  attr_accessor :filter
  attr_accessor :messages
  attr_reader :client
  attr_reader :options

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

  def logger
    @logger ||= LoggerWithTrace.new(@options[:logger] ? $stdout : StringIO.new).setup(
      progname: self.class.name,
      level: @options[:logger_level] || :info
    )
  end

  def connect!
    raise "Waithook connection already started" if @started
    @started = true
    @client.connect!.wait_handshake!
    self
  end

  def started?
    !!@started
  end

  def forward_to(url, options = {})
    webhook = wait_message(options)
    webhook.send_to(url) unless webhook.nil?
  end

  def wait_message(options = {})
    raise_timeout_error = options.has_key?(:raise_timeout_error) ? options[:raise_timeout_error] : true
    timeout = options[:timeout] || @options[:timeout] || 0

    start_time = Time.new.to_f
    Timeout.timeout(timeout) do
      while true
        type, data = @client.wait_message
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

  def close!
    @client.close!
    @started = false
  end

  class Webhook
    attr_reader :url
    attr_reader :headers
    attr_reader :body
    attr_reader :method

    def initialize(payload)
      data = JSON.parse(payload)
      @url = data['url']
      @headers = data['headers']
      @body = data['body']
      @method = data['method']
    end

    def json_body
      if @body
        @json_body ||= JSON.parse(@body)
      end
    end

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
          when "HEAD"   then Net::HTTP::Head
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
