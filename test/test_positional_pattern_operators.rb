# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

class TestPositionalPatternOperators < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_idiom') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  # pattern operators on positional and special parameters
  def test_pattern_operators_on_positional_parameters
    @repl.positional_params = ['/a/b/c.txt']
    @repl.script_name = '/usr/bin/rubish'
    assert_equal "c.txt rubish /a/b\n", run_and_read('echo "${1##*/}" "${0##*/}" "${1%/*}"')
  end
end
