
task :test do
  Dir.glob('./tests/**/*_test.rb').each { |file| require file }
end

task :doc do
  `rdoc -f hanna lib/* -m README.md`
end