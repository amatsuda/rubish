# frozen_string_literal: true

require_relative 'test_helper'

# ${arr[*]@k} is the unquoted form of @K: key value pairs
class TestParamTransformK < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_lowercase_k_transform
    out = capture_stdout { execute('a=(x y); echo "${a[*]@k}"; declare -A m=([k]=v); echo "${m[@]@k}"') }
    assert_equal "0 x 1 y\nk v\n", out
  end
end
