# frozen_string_literal: true

require_relative 'test_helper'

# `set -o` lists the options in alphabetical order, as bash does
class TestSetOListingSorted < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_sorted
    out = capture_stdout { execute('set -o') }
    names = out.lines.map { |l| l.split.first }
    assert_equal names.sort, names
    assert_includes names, 'errexit'
  end
end
