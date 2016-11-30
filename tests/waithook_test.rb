require_relative 'test_helper'

describe "Waithook" do

  before do
    @waithook_instances = []
  end

  after do
    @waithook_instances.map(&:close!).clear
  end

  def default_client(options = {})
    client = Waithook.subscribe({path: 'my-super-test', host: HOST, port: PORT, logger: false}.merge(options))
    @waithook_instances.push(client)
    client
  end

  it "should subscribe" do
    waithook = default_client

    stats = get_stats
    assert_equal(1, stats['total_listeners'])
    assert_equal({"/my-super-test" => 1}, stats['listeners'])
  end

  it "should receive a message" do
    waithook = default_client

    message = JSON.generate([Time.now.to_s])
    Excon.post("http://#{HOST}:#{PORT}/my-super-test", body: message)

    webhook = waithook.wait_message
    assert_instance_of(Waithook::Webhook, webhook)
    assert_equal(message, webhook.body)
    assert_equal(JSON.parse(message), webhook.json_body)
  end

  it "should forward request" do
    waithook = default_client
    second_client = default_client(path: 'my-super-test2')

    message = {'my_data' => true}

    Excon.post("http://#{HOST}:#{PORT}/my-super-test", body: JSON.generate(message))

    server_response = waithook.forward_to("http://#{HOST}:#{PORT}/my-super-test2")

    assert_instance_of(Net::HTTPOK, server_response)
    assert_equal("OK\n", server_response.body)

    webhook = second_client.wait_message

    assert_equal(message, webhook.json_body)
    assert_equal("POST", webhook.method)
  end

  it "should have trace log level" do
    out, err = capture_io do
      default_client(logger_level: :trace, logger: true)
    end

    assert_includes(out, 'Sec-WebSocket-Version')
  end

  it "should be more quiet generally" do
    out, err = capture_io do
      default_client(logger: true)
    end

    refute_includes(out, 'Sec-WebSocket-Version')
  end

  it "wait_message should raise exception after timeout" do
    assert_raises(Timeout::Error) do
      default_client.wait_message(timeout: 0.1)
    end
  end

  it "wait_message should return nil after timeout" do
    waithook = default_client
    assert_equal(nil, waithook.wait_message(timeout: 0.1, raise_on_timeout: false))
  end

  it "forward_to should raise exception after timeout" do
    assert_raises(Timeout::Error) do
      default_client.forward_to('', timeout: 0.1)
    end
  end

  it "forward_to should return nil after timeout" do
    out, err = capture_io do
      waithook = default_client(logger: true)
      assert_equal(nil, waithook.forward_to('', timeout: 0.1, raise_on_timeout: false))
    end

    assert_includes(out, "Timeout::Error: execution expired")
  end
end
