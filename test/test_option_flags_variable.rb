# frozen_string_literal: true

require_relative 'test_helper'

# $- lists the set options in bash's order: histexpand only when interactive,
# and `c` for a shell started with -c
class TestOptionFlagsVariable < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_flags_in_c_mode
    assert_equal "hBc\nhuBc\n", run_shell('echo $-; set -u; echo $-')
  end
end
