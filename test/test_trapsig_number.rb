# frozen_string_literal: true

require_relative 'test_helper'

# BASH_TRAPSIG holds the number of the signal being handled
class TestTrapsigNumber < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_trapsig_is_numeric
    # USR1 is 30 on macOS and 10 on Linux
    assert_equal "sig=#{Signal.list['USR1']}\n", run_shell("trap 'echo \"sig=$BASH_TRAPSIG\"' USR1; kill -USR1 $$")
  end
end
