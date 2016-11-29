require 'logger'

# Just add trace level
class LoggerWithTrace < ::Logger
  module Severity
    include ::Logger::Severity
    TRACE = -1
  end

  TRACE = Severity::TRACE

  def trace(progname = nil, &block)
    add(TRACE, nil, progname, &block)
  end

  def trace?
    @level <= TRACE
  end

  def level=(severity)
    if severity.is_a?(Integer)
      @level = severity
    else
      @level = case severity.to_s.downcase
      when 'trace'.freeze   then TRACE
      when 'debug'.freeze   then DEBUG
      when 'info'.freeze    then INFO
      when 'warn'.freeze    then WARN
      when 'error'.freeze   then ERROR
      when 'fatal'.freeze   then FATAL
      when 'unknown'.freeze then UNKNOWN
      else
        raise ArgumentError, "invalid log level: #{severity}"
      end
    end
  end
end