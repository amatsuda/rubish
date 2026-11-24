# frozen_string_literal: true

require_relative 'test_helper'

# `kill -n N` sends signal number N
class TestKillNOption < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_kill_n
    assert_equal "got\ngot\nend\n", run_shell("trap 'echo got' SIGUSR1; kill -s USR1 $$; kill -n #{Signal.list['USR1']} $$; echo end") # USR1 is 30 on macOS, 10 on Linux
  end
end
