# frozen_string_literal: true

require_relative 'test_helper'

# `readonly NAME=value` creates a shell variable; it does not export it
class TestReadonlyNotExported < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    ENV.delete('RO_NE_T')
  end

  def test_readonly_assignment_stays_out_of_the_environment
    execute('readonly RO_NE_T=1')
    assert_nil ENV['RO_NE_T']
    assert_equal '1', get_shell_var('RO_NE_T')
    out = capture_stdout { execute('declare -p RO_NE_T') }
    assert_equal %(declare -r RO_NE_T="1"\n), out
  end
end
