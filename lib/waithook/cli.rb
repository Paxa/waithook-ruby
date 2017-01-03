class Waithook
  module WithColor #:nodoc:
    extend self
    def black(s);   "\033[30m#{s}\033[0m" end
    def red(s);     "\033[31m#{s}\033[0m" end
    def green(s);   "\033[32m#{s}\033[0m" end
    def brown(s);   "\033[33m#{s}\033[0m" end
    def blue(s);    "\033[34m#{s}\033[0m" end
    def magenta(s); "\033[35m#{s}\033[0m" end
    def cyan(s);    "\033[36m#{s}\033[0m" end
    def gray(s);    "\033[37m#{s}\033[0m" end
    def yellow(s);  "\033[93m#{s}\033[0m" end
    def bold(s);    "\e[1m#{s}\e[m"       end
  end

  module CLI #:nodoc:
    class ArgError < ArgumentError; end #:nodoc:

    extend self

    def listen(url, options)
      puts "Run with options: #{options}" if options[:verbose]
      unless url.start_with?('ws://', 'wss://')
        url = 'wss://' + url
      end

      unless url =~ /\A#{URI::regexp(['ws', 'wss'])}\z/
        raise ArgError, "#{url.inspect} is not a valid websocket URL"
      end

      uri = URI.parse(url)
      port = uri.scheme == 'wss' ? 443 : uri.port
      path = uri.path.start_with?('/') ? uri.path.sub(/^\//, '') : uri.path
      logger_level = options[:verbose] ? 'trace' : 'warn'

      puts WithColor.green("Connecting to #{url}")
      waithook = Waithook.new(host: uri.host, port: port, path: path, logger_level: logger_level)
      puts WithColor.green("Connected! Waiting to for message...") if waithook.client.wait_connected

      while true
        message = waithook.wait_message
        puts message.message
        if options[:forward]
          Thread.new do
            begin
              forward_url = if options[:forward].start_with?('http://', 'https://')
                forward_url
              else
                "http://#{options[:forward]}"
              end

              puts WithColor.brown("Sending as HTTP to #{forward_url}")
              response = message.send_to(forward_url)
              puts WithColor.brown("Reponse from #{forward_url} -> #{WithColor.bold("#{response.code} #{response.message}")}")
            rescue => error
              puts WithColor.red("#{error.message} (#{error.class})")
              puts WithColor.red(error.backtrace.join("\n"))
            end
          end
        end
      end
    end
  end
end