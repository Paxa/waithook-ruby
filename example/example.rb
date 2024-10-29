require 'looksee'
require 'net/http'

require_relative '../lib/waithook/websocket_client'

HOST = 'localhost'
PORT = 3012
#HOST = 'waithook.com'
#PORT = 80

client = WebsocketClient.new(host: HOST, port: PORT, path: 'test-ruby')

client.connect!

sleep 1

client.send_ping!

def print_time(message)
  s_time = Time.now.to_f
  r = yield
  puts "Time #{message}: #{Time.now.to_f - s_time}"
  r
end

sleep 5

Net::HTTP.start(HOST, PORT) do |http|
  while true
    sleep 2
    print_time("HTTP Request") {
      http.get("/test-ruby")
    }
    print_time("Waithook response") {
      type, data = client.wait_message
      #p [type, data]
    }
    #client.close!
    #Net::HTTP.get(URI.parse("http://#{HOST}:#{PORT}/test-ruby"))
  end
end

#socket = TCPSocket.open(hostname, port)
#
#request = WebSocket::Handshake::Client.new(url: 'ws://waithook.com/test-ruby')
#puts request
#
#socket.print(request)
#
#while line = socket.gets
#  puts line.chop
#end
#
#socket.close
