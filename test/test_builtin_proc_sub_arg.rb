# frozen_string_literal: true

require_relative 'test_helper'

# A builtin run on the REPL fast path gets a process substitution argument
# expanded like any other word, not as a raw AST node
class TestBuiltinProcSubArg < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_substitution_expands_to_a_dev_fd_path
    out = capture_stdout { execute('echo <(true)') }
    assert_match(%r{\A/dev/fd/\d+\n\z}, out)
  end

  def test_descriptor_is_closed_after_the_command
    out = capture_stdout { execute('echo <(true)') }
    fd = out[%r{/dev/fd/(\d+)}, 1].to_i
    capture_stdout { execute('true') }
    assert_raise(Errno::EBADF, ArgumentError) { IO.for_fd(fd, autoclose: false).fstat }
  end
end
