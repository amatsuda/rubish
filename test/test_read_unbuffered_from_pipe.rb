# frozen_string_literal: true

require_relative 'test_helper'

# `read` takes only its own line from a pipe, leaving the rest for the
# commands that follow in the same group
class TestReadUnbufferedFromPipe < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_rest_of_the_pipe_reaches_the_next_command
    assert_equal "1+2\n3\n", run_shell("printf '1\\n2\\n3\\n' | { read a; read b; echo \"$a+$b\"; cat; }")
  end

  def test_read_with_a_delimiter_leaves_the_rest
    assert_equal "a\nb,c\n", run_shell("printf 'a,b,c\\n' | { read -d , x; echo \"$x\"; cat; }")
  end
end
