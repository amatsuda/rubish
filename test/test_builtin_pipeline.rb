# frozen_string_literal: true

require_relative 'test_helper'

# Regression tests for builtins used in pipelines
# Previously, builtins like `history` would fail with "command not found"
# when used as the first command in a pipeline (e.g., `history | grep foo`)
class TestBuiltinPipeline < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_builtin_pipeline_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def execute(line)
    @repl.send(:execute, line)
    @repl.instance_variable_get(:@last_status)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test `echo` builtin in pipeline
  def test_echo_piped_to_cat
    execute("echo 'hello world' | cat > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  def test_echo_piped_to_grep
    execute("echo 'hello world' | grep hello > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  def test_echo_piped_to_wc
    execute("echo 'hello' | wc -c > #{output_file}")
    # 'hello\n' is 6 characters
    assert_equal 6, File.read(output_file).strip.to_i
  end

  # Test `printf` builtin in pipeline
  def test_printf_single_arg_piped
    execute("printf 'hello' | cat > #{output_file}")
    assert_equal 'hello', File.read(output_file)
  end

  def test_printf_with_format_piped
    execute("printf '%s:%s\\n' a b | cat > #{output_file}")
    assert_equal "a:b\n", File.read(output_file)
  end

  # Test `pwd` builtin in pipeline
  def test_pwd_piped_to_cat
    execute("pwd | cat > #{output_file}")
    content = File.read(output_file).strip
    assert_equal Dir.pwd, content
  end

  # Test `type` builtin in pipeline
  def test_type_piped_to_cat
    execute("type cd | cat > #{output_file}")
    content = File.read(output_file)
    assert_match(/cd/, content)
    assert_match(/builtin/, content)
  end

  def test_type_piped_to_grep
    execute("type echo | grep builtin > #{output_file}")
    content = File.read(output_file)
    assert_match(/builtin/, content)
  end

  # Test `alias` builtin in pipeline
  def test_alias_piped_to_grep
    execute("alias mytest='echo hello'")
    execute("alias | grep mytest > #{output_file}")
    content = File.read(output_file)
    assert_match(/mytest/, content)
    assert_match(/echo hello/, content)
  end

  def test_alias_list_piped_to_wc
    execute("alias a1='echo 1'")
    execute("alias a2='echo 2'")
    execute("alias a3='echo 3'")
    execute("alias | wc -l > #{output_file}")
    count = File.read(output_file).strip.to_i
    assert count >= 3, "Expected at least 3 aliases, got #{count}"
  end

  # Test `jobs` builtin in pipeline (even with no jobs)
  def test_jobs_piped_to_cat
    # jobs with no background jobs should produce no output (not an error)
    status = execute("jobs | cat > #{output_file}")
    assert_equal 0, status
  end

  # Test `help` builtin in pipeline
  def test_help_piped_to_cat
    execute("help cd | cat > #{output_file}")
    content = File.read(output_file)
    assert_match(/cd/i, content)
  end

  def test_help_piped_to_grep
    execute("help echo | grep -i 'write' > #{output_file}")
    content = File.read(output_file)
    # help echo should mention writing to stdout
    assert content.length > 0, "Expected help output to match 'write'"
  end

  # Test `true` and `false` builtins in pipeline
  def test_true_piped
    status = execute("true | cat > #{output_file}")
    assert_equal 0, status
  end

  def test_false_piped
    status = execute("false | cat > #{output_file}")
    # Pipeline status is the last command's status
    assert_equal 0, status
  end

  # Test `test` / `[` builtin in pipeline
  def test_test_builtin_piped
    # test doesn't produce output, but should not error
    status = execute("test -d /tmp | cat > #{output_file}")
    assert_equal 0, status
  end

  # Test builtin as middle command in pipeline
  def test_builtin_in_middle_of_pipeline
    execute("echo 'hello' | cat | cat > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # Test multiple builtins chained
  def test_echo_piped_through_cat_twice
    execute("echo 'test' | cat | cat | cat > #{output_file}")
    assert_equal "test\n", File.read(output_file)
  end

  # Test that `history` command is recognized (not "command not found")
  # Note: history list may be empty in test environment, but command should execute
  def test_history_recognized_in_pipeline
    # This should NOT produce "command not found" error
    output = capture_stderr do
      execute("history 1 | cat > #{output_file}")
    end
    refute_match(/command not found/, output)
  end

  # Test `declare` builtin in pipeline
  def test_declare_piped_to_grep
    execute('export TESTVAR_PIPELINE_UNIQUE=testvalue')
    execute("declare -p TESTVAR_PIPELINE_UNIQUE | cat > #{output_file}")
    content = File.read(output_file)
    assert_match(/TESTVAR_PIPELINE_UNIQUE/, content)
  end

  # Test `set` builtin with -o in pipeline
  def test_set_options_piped
    execute("set -o | cat > #{output_file}")
    content = File.read(output_file)
    # Should list various options
    assert content.length > 0, 'Expected set -o to produce output'
  end

  # Test `shopt` builtin in pipeline
  def test_shopt_piped_to_grep
    execute("shopt | grep -E '(on|off)' > #{output_file}")
    content = File.read(output_file)
    assert content.length > 0, 'Expected shopt output'
  end
end
