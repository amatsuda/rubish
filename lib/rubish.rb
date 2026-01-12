# frozen_string_literal: true

require 'set'
require 'stringio'
require 'tempfile'
require 'tmpdir'
require 'singleton'
require 'fileutils'
require 'socket'
require 'timeout'
require 'securerandom'
require 'etc'
require 'shellwords'
require 'io/console'
require 'syslog'
require 'reline'

# Suppress deprecation warnings for Data class on Ruby < 3.2
if RUBY_VERSION < '3.2'
  verbose_was, $VERBOSE = $VERBOSE, nil
  begin
    require_relative 'rubish/data_define'
    require_relative 'rubish/lexer'
    require_relative 'rubish/ast'
  ensure
    $VERBOSE = verbose_was
  end
else
  require_relative 'rubish/lexer'
  require_relative 'rubish/ast'
end

require_relative 'rubish/parser'
require_relative 'rubish/codegen'
require_relative 'rubish/runtime/command'
require_relative 'rubish/runtime/job'
require_relative 'rubish/runtime/builtins'
require_relative 'rubish/repl'

module Rubish
  VERSION = '0.0.1'
end
