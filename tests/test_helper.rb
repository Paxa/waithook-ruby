Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8

require 'bundler/setup'
require_relative '../lib/waithook'

require 'excon'
require 'json'
require "minitest/autorun"
require "minitest/reporters"
require "addressable/uri"

Minitest::Reporters.use!(
  Minitest::Reporters::SpecReporter.new(color: true)
)

if ENV['SEQ']
  puts "Set test_order == :alpha"
  class Minitest::Test
    def self.test_order
     :alpha
    end
  end
end

# To support UTF-8 in path
module WebSocket::Handshake
  URI = Addressable::URI
end

HOST = 'localhost'
PORT = 3012
PATH = 'test-ruby'

def POST(path, data = nil)
  Excon.post("http://#{HOST}:#{PORT}/#{path}", body: data, uri_parser: Addressable::URI)
end

def GET(path)
  Excon.get("http://#{HOST}:#{PORT}/#{path}", uri_parser: Addressable::URI)
end

def get_stats
  JSON.parse(GET('@/stats').body)
end
