require 'net/http'
require 'json'

require_relative 'waithook/websocket_client'

class Waithook

  SERVER_HOST = "waithook.herokuapp.com"
  SERVER_PORT = 443

  def self.subscribe(path, options = {}, &block)
    instance = new(path, options)
    if block
      instance.filter = block
    end
    instance.connect! unless instance.started?
    instance
  end

  attr_accessor :filter
  attr_accessor :messages
  attr_reader :client

  def initialize(path, options = {})
    options = {
      host: SERVER_HOST,
      port: SERVER_PORT,
      auto_connect: true
    }.merge(options)

    @path = path
    @client = WebsocketClient.new(
      path: path,
      host: options[:host],
      port: options[:port],
      logger: options[:logger]
    )

    @messages = []
    @filter = nil
    @started = false

    connect! if options[:auto_connect]
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

  def forward_to(url)
    webhook = wait_message

    uri = URI.parse(url)
    response = nil

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http_klass = case webhook.method
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
      webhook.headers.each do |key, value|
        request[key] = value
      end

      if webhook.body
        request.body = webhook.body
      end

      response = http.request(request)
    end

    response
  end

  def wait_message
    while true
      type, data = @client.wait_message
      webhook = Webhook.new(data)
      if @filter && @filter.call(webhook) || !@filter
        @messages << webhook
        return webhook
      end
    end
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
  end
end
