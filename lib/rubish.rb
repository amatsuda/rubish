# frozen_string_literal: true

require 'set'
require 'stringio'
require 'tempfile'
require 'tmpdir'
require 'singleton'
require 'fileutils'
require 'timeout'
require 'shellwords'
require 'io/console'
require 'reline'

require_relative 'rubish/lexer'
require_relative 'rubish/ast'
require_relative 'rubish/parser'
require_relative 'rubish/codegen'
require_relative 'rubish/runtime/command'
require_relative 'rubish/runtime/job'
require_relative 'rubish/runtime/builtins'
require_relative 'rubish/repl'

module Rubish
  VERSION = '0.0.1'
end
