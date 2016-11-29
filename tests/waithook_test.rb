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
end
