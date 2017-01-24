require 'looksee'
require 'excon'

require './websocket-client'

#HOST = 'localhost'
#PORT = 3012
HOST = 'waithook.com'
PORT = 80

client = WebsocketClient.new(host: HOST, port: PORT, path: 'test-ruby').connect!.wait_handshake!

Excon.get("http#{PORT == 443 ? 's' : ''}://#{HOST}:#{PORT}/test-ruby")
type, data = client.wait_message

puts "Received message (#{type})"
puts "Received message body: #{data}"

client.close!
