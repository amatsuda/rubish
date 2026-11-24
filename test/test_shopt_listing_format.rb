# frozen_string_literal: true

require_relative 'test_helper'

# `shopt name` lists like bash: the name padded to 20 columns, a tab, on/off
class TestShoptListingFormat < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('shopt -u extglob')
  end

  def test_padded_name
    out = capture_stdout { execute('shopt -s extglob; shopt extglob; shopt -u extglob; shopt extglob') }
    assert_equal "extglob             \ton\nextglob             \toff\n", out
  end
end
