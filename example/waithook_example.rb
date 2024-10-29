require_relative '../lib/waithook'
require 'excon'

waithook = Waithook.subscribe(path: 'my-super-test', host: 'localhost', port: 3012)

Excon.post('http://localhost:3012/my-super-test', body: Time.now.to_s)

while true
  response = waithook.forward_to('http://localhost:3012/my-super-test')
  p waithook.messages.last
end
