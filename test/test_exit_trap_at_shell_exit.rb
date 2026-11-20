# frozen_string_literal: true

require_relative 'test_helper'

# The EXIT trap runs when the shell finishes, not only on an explicit `exit`
class TestExitTrapAtShellExit < Test::Unit::TestCase
  RUBISH = File.expand_path('../exe/rubish', __dir__)

  def run_rubish(*args, stdin: nil)
    out_r, out_w = IO.pipe
    in_r, in_w = IO.pipe
    pid = Process.spawn(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), RUBISH, *args,
                        in: in_r, out: out_w, err: out_w)
    out_w.close
    in_r.close
    in_w.write(stdin) if stdin
    in_w.close
    output = out_r.read
    Process.wait(pid)
    [output, $?.exitstatus]
  end

  def test_exit_trap_runs_at_end_of_dash_c
    out, status = run_rubish('-c', 'trap "echo EXIT_TRAP" EXIT; echo body')
    assert_equal "body\nEXIT_TRAP\n", out
    assert_equal 0, status
  end

  def test_exit_trap_runs_once_with_explicit_exit
    out, status = run_rubish('-c', 'trap "echo EXIT_TRAP" EXIT; exit 3')
    assert_equal 1, out.scan('EXIT_TRAP').size
    assert_equal 3, status
  end

  def test_exit_trap_runs_at_end_of_script_file
    Dir.mktmpdir('rubish_exit_trap') do |dir|
      script = File.join(dir, 's.sh')
      File.write(script, "trap 'echo cleanup' EXIT\necho work\n")
      out, status = run_rubish(script)
      assert_equal "work\ncleanup\n", out
      assert_equal 0, status
    end
  end

  def test_exit_trap_runs_at_end_of_stdin_mode
    out, = run_rubish('-s', stdin: "trap 'echo bye' EXIT\necho hi\n")
    assert_equal "hi\nbye\n", out
  end

  def test_exit_status_is_preserved_across_the_trap
    _, status = run_rubish('-c', 'trap "true" EXIT; false')
    assert_equal 1, status
  end
end
