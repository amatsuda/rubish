# frozen_string_literal: true

require_relative 'test_helper'

# `read` assigns the shell variable, so a variable set earlier is replaced
# and the variable is not exported
class TestReadIntoExistingVariable < Test::Unit::TestCase
  def test_existing_variable_is_replaced
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'x=1; read x <<< y; echo "[$x]"; v=1; read -t 1 v <<< w; echo "[$v]"; read -t 1 q < /dev/null; read -t 0.1 q <<< z; echo "[$q]"', err: %i[child out]], &:read)
    assert_equal "[y]\n[w]\n[z]\n", out
  end

  def test_not_exported
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'read r <<< val; declare -p r; env | grep -c "^r=val"', err: %i[child out]], &:read)
    assert_equal "declare -- r=\"val\"\n0\n", out
  end
end
