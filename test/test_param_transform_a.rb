# frozen_string_literal: true

require_relative 'test_helper'

# ${var@a} lists every attribute of the variable
class TestParamTransformA < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_integer_and_array_attributes
    out = capture_stdout { execute('declare -i i=5; declare -r r=1; declare -x x=2; declare -a a=(1); declare -A h=([k]=v); echo "${i@a} ${r@a} ${x@a} ${a@a} ${h@a}"') }
    assert_equal "i r x a A\n", out
  end
end
