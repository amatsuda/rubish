# frozen_string_literal: true

require_relative 'rubish/version'

require 'set'
require 'stringio'
require 'singleton'
require 'fileutils'
require 'socket'
require 'timeout'
require 'securerandom'
require 'etc'
require 'shellwords'
require 'io/console'
require 'reline'
require 'did_you_mean'

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
require_relative 'rubish/array_word'
require_relative 'rubish/codegen'
require_relative 'rubish/runtime/command'
require_relative 'rubish/runtime/job'
require_relative 'rubish/runtime/builtins'
require_relative 'rubish/frontend'
require_relative 'rubish/repl'

module Rubish
  # `$$` is the pid of the shell that was started, in subshells too
  SHELL_PID = Process.pid

  # Load a library on demand from code mixed into the shell context.
  # There a bare `require` is the shell builtin, and Kernel.require is the
  # pristine C implementation that bypasses RubyGems, so bundled gems such as
  # fiddle and syslog cannot be found through it outside Bundler. Resolving
  # `require` on this module reaches the RubyGems-aware Kernel#require.
  def self.require_library(name)
    require name
  end

  # Set a custom prompt function
  # Usage: Rubish.set_prompt { "#{Dir.pwd}> " }
  def self.set_prompt(&block)
    REPL.prompt_proc = block
    nil
  end

  # Set a custom right prompt function
  # Usage: Rubish.set_right_prompt { git_prompt_info }
  def self.set_right_prompt(&block)
    REPL.right_prompt_proc = block
    nil
  end
end
