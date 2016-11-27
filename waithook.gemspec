require_relative 'lib/waithook/version'

Gem::Specification.new do |s|
  s.name        = "waithook"
  s.version     = Waithook::VERSION
  s.author      = ["Pavel Evstigneev"]
  s.email       = ["pavel.evst@gmail.com"]
  s.homepage    = "https://github.com/paxa/waithook-ruby"
  s.summary     = %q{HTTP to WebSocket transmitting client}
  s.description = "Waithook gem is client lib for waithook service https://waithook.heroku.com"
  s.license     = 'MIT'

  s.files       = `git ls-files`.split("\n")
  s.test_files  = []

  s.require_paths = ["lib"] 
  s.executables   = ["waithook"]

  s.add_runtime_dependency "websocket", "~> 1.2"
end
