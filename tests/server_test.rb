require_relative 'test_helper'

describe "Server" do
  after do
    @client.close! if @client && @client.connected?
    assert_equal(0, get_stats['total_listeners'])
  end

  def default_client
    Waithook::WebsocketClient.new(host: HOST, port: PORT, path: PATH, output: StringIO.new).connect!.wait_handshake!
  end

  it "should remove connection on disconnect with close frame" do
    @client = default_client

    POST(PATH, 'test data')
    type, data = @client.wait_message
    message = JSON.parse(data)

    assert_equal(:text, type)
    assert_equal('test data', message['body'])

    @client.close!

    assert_equal(0, get_stats['total_listeners'])
  end

  it "should remove connection after disconnect without close frame" do
    @client = default_client

    POST(PATH, 'test data')
    type, data = @client.wait_message
    message = JSON.parse(data)

    assert_equal(:text, type)
    assert_equal('test data', message['body'])

    @client.close!(send_close: false)

    assert_equal(0, get_stats['total_listeners'])
  end

  it "should show stats for subscribed connection" do
    @client = default_client

    response = GET('@/stats')
    stats = JSON.parse(response.body)
    @client.close!

    assert_equal({'/test-ruby' => 1}, stats['listeners'])
    assert_equal({
      "Connection"     => "close",
      "Content-Length" => "116",
      "Content-Type"   => "application/json"
    }, response.headers)
  end

  it "should not allow keep-alive" do
    response = POST(PATH, 'test data')

    assert_equal("OK\n", response.body)
    assert_equal({
      "Connection"     => "close",
      "Content-Length" => "3",
      "Content-Type"   => "text/plain"
    }, response.headers)
  end

  it "should serve index.html" do
    response = GET("")

    assert_includes(response.body, "<html>")
    assert_equal({
      "Connection"     => "close",
      "Content-Length" => response.headers["Content-Length"],
      "Content-Type"   => "text/html"
    }, response.headers)
  end

  it "should serve index.html" do
    response = GET("@/index.js")

    assert_includes(response.body, "function")
    assert_equal({
      "Connection"     => "close",
      "Content-Length" => response.headers["Content-Length"],
      "Content-Type"   => "application/javascript; charset=utf-8"
    }, response.headers)
  end

  it "should support utf-8 content" do
    @client = default_client

    response = POST(PATH, "привет")
    assert_includes(response.body, "OK\n")

    type, data = @client.wait_message
    message = JSON.parse(data)

    assert_equal(:text, type)
    assert_equal("привет", message['body'])
  end

  it "should support utf-8 paths" do
    skip "hyper not support it yet"
    path = "бум!!!"
    @client = Waithook::WebsocketClient.new(host: HOST, port: PORT, path: path, output: StringIO.new).connect!
    @client.wait_handshake!

    response = POST(path, "test-body")
    assert_includes(response.body, "OK\n")

    type, data = @client.wait_message
    message = JSON.parse(data)

    assert_equal(:text, type)
    assert_equal("test-body", message['body'])
  end

  it "should work with PUT" do
    @client = default_client
    response = Excon.put("http://#{HOST}:#{PORT}/#{PATH}", body: "test-data")

    type, data = @client.wait_message
    message = JSON.parse(data)

    assert_equal(:text, type)
    assert_equal("test-data", message['body'])
    assert_equal("PUT", message['method'])
  end
end
