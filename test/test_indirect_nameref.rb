# frozen_string_literal: true

require_relative 'test_helper'

class TestIndirectNameref < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # ${!ref} on a nameref yields the name it refers to
  def test_indirect_expansion_of_a_nameref
    execute('declare -n ref_i=target_i; target_i=val')
    out = capture_stdout { execute('echo "${!ref_i}"') }
    assert_equal "target_i\n", out
  end
end
