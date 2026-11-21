# frozen_string_literal: true

require_relative 'test_helper'

# `set -o` lists options as a table of name and on/off; `set +o` prints
# reusable `set -o name` / `set +o name` commands, as in bash
class TestSetOListing < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_set_dash_o_prints_a_name_state_table
    out = capture_stdout { execute('set -o') }
    lines = out.lines.map(&:chomp)
    assert_not_empty lines
    lines.each { |l| assert_match(/\A[a-z]+\s+(on|off)\z/, l) }
    assert_includes lines.map { |l| l.split }, %w[braceexpand on]
  end

  def test_set_plus_o_prints_reusable_commands
    out = capture_stdout { execute('set +o') }
    lines = out.lines.map(&:chomp)
    assert_not_empty lines
    lines.each { |l| assert_match(/\Aset [+-]o [a-z]+\z/, l) }
    assert_includes lines, 'set -o braceexpand'
  end
end
