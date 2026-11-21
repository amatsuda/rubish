# frozen_string_literal: true

require_relative 'test_helper'

class TestDeclareCapitalFFormat < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # declare -F prints `declare -f name` per function
  def test_declare_capital_f_listing_format
    execute('fa_df() { :; }; fb_df() { :; }')
    out = capture_stdout { execute('declare -F') }
    assert_includes out.lines, "declare -f fa_df\n"
    assert_includes out.lines, "declare -f fb_df\n"
  end
end
