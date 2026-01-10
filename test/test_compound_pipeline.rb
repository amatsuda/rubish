# frozen_string_literal: true

require_relative 'test_helper'

class TestCompoundPipeline < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_compound_pipeline_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def execute(line)
    @repl.send(:execute, line)
    @repl.instance_variable_get(:@last_status)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # For loop in pipeline (output side)
  def test_for_loop_piped_to_command
    execute("for i in a b c; do echo $i; done | cat -n > #{output_file}")
    content = File.read(output_file)
    assert_match(/1.*a/, content)
    assert_match(/2.*b/, content)
    assert_match(/3.*c/, content)
  end

  def test_for_loop_piped_to_grep
    execute("for i in apple banana cherry; do echo $i; done | grep an > #{output_file}")
    assert_equal "banana\n", File.read(output_file)
  end

  def test_for_loop_piped_to_wc
    execute("for i in 1 2 3 4 5; do echo $i; done | wc -l > #{output_file}")
    assert_equal '5', File.read(output_file).strip
  end

  # While loop in pipeline (input side)
  def test_while_read_from_pipe
    execute("echo -e 'line1\\nline2\\nline3' | while read x; do echo got: $x; done > #{output_file}")
    content = File.read(output_file)
    # Note: echo -e may not work if xpg_echo is disabled, but the piping should work
    assert content.include?('got:')
  end

  def test_while_counting_lines
    execute("printf 'a\\nb\\nc\\n' | while read line; do echo $line; done > #{output_file}")
    assert_equal "a\nb\nc\n", File.read(output_file)
  end

  # Select loop in pipeline
  def test_select_reads_from_pipe
    old_stdin = $stdin
    # Select will read "1" from stdin (via the pipe), selecting the first item
    execute("echo 1 | select x in first second third; do echo $x; break; done > #{output_file}")
    content = File.read(output_file)
    # Output includes the menu and the selected item
    assert content.include?('first'), "Expected 'first' in output, got: #{content}"
  ensure
    $stdin = old_stdin
  end

  # If statement in pipeline
  def test_if_in_pipeline_output
    execute("if true; then echo yes; else echo no; fi | cat > #{output_file}")
    assert_equal "yes\n", File.read(output_file)
  end

  def test_if_in_pipeline_input
    execute("echo success | if read x; then echo got: $x; fi > #{output_file}")
    assert_equal "got: success\n", File.read(output_file)
  end

  # Case statement in pipeline
  def test_case_in_pipeline
    execute("case foo in foo) echo matched;; esac | cat > #{output_file}")
    assert_equal "matched\n", File.read(output_file)
  end

  # Arithmetic for loop in pipeline
  def test_arith_for_in_pipeline
    execute("for ((i=1; i<=3; i++)); do echo $i; done | cat -n > #{output_file}")
    content = File.read(output_file)
    assert_match(/1.*1/, content)
    assert_match(/2.*2/, content)
    assert_match(/3.*3/, content)
  end

  # Until loop in pipeline
  def test_until_in_pipeline
    execute("i=0; until (( i >= 3 )); do echo $i; (( i++ )); done | cat > #{output_file}")
    assert_equal "0\n1\n2\n", File.read(output_file)
  end

  # Multiple compound commands in pipeline
  def test_for_to_while_pipeline
    execute("for i in 1 2 3; do echo $i; done | while read x; do echo num: $x; done > #{output_file}")
    content = File.read(output_file)
    assert_equal "num: 1\nnum: 2\nnum: 3\n", content
  end

  # Compound command in middle of pipeline
  def test_compound_in_middle
    execute("echo start; for i in a b; do echo $i; done | cat | wc -l > #{output_file}")
    # Should count 2 lines (a and b)
    assert_equal '2', File.read(output_file).strip
  end

  # Exit status from compound pipeline
  def test_pipeline_exit_status_success
    status = execute('for i in 1; do true; done | cat')
    assert_equal 0, status
  end

  def test_pipeline_exit_status_last_command
    status = execute('for i in 1; do echo $i; done | false')
    assert_equal 1, status
  end

  # Subshell in pipeline (should still work)
  def test_subshell_in_pipeline
    execute("(echo hello; echo world) | cat -n > #{output_file}")
    content = File.read(output_file)
    assert_match(/1.*hello/, content)
    assert_match(/2.*world/, content)
  end
end
