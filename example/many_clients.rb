require 'looksee'
require 'net/http'
require "stringio"
require 'json'

require './websocket-client'

HOST = 'localhost'
PORT = 3012
#HOST = 'waithook.herokuapp.com'
#PORT = 80

threads_num = ENV['THREADS'] ? ENV['THREADS'].to_i : 10
threads = []
timing = {}
running = true

threads_num.times do
  threads << Thread.new do
    begin
      client = WebsocketClient.new(host: HOST, port: PORT, path: 'pick-hour', output: StringIO.new)
      client.connect!

      while running
        type, data = client.wait_message
        body = JSON.parse(data)['body']
        puts "Message time: #{Time.now.to_f - timing[body]} sec"
      end

      client.close!
      puts "client done"
    rescue Object => error
      puts "#{error.class}: #{error.message}\n#{error.backtrace.join("\n")}"
      raise error
    end
  end
end

sleep 3

Net::HTTP.start(HOST, PORT) do |http|
  200.times do |n|
    msg = "aaa-#{n}"
    timing[msg] = Time.now.to_f
    puts "Sending #{msg}"
    puts http.post('/pick-hour', msg)
    sleep 0.05
  end
end

#200.times do |n|
#  msg = "aaa-#{n}"
#  timing[msg] = Time.now.to_f
#  puts "Sending #{msg}"
#  Net::HTTP.start(HOST, PORT) do |http|
#    puts http.post('/pick-hour', msg)
#  end
#  sleep 0.01
#end

#Net::HTTP.get(URI.parse("http://#{HOST}:#{PORT}/pick-hour"))

#p threads
threads.map(&:join)
