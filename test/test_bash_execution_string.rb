# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_EXECUTION_STRING < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_execution_string_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_EXECUTION_STRING functionality

  def test_bash_execution_string_empty_by_default
    # In interactive mode, BASH_EXECUTION_STRING should be empty
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${BASH_EXECUTION_STRING}x\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'xx', content, 'BASH_EXECUTION_STRING should be empty in interactive mode'
  end

  def test_bash_execution_string_when_set
    # Simulate -c mode by setting the env var
    ENV['RUBISH_EXECUTION_STRING'] = 'echo hello world'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_EXECUTION_STRING > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'echo hello world', content
  end

  def test_bash_execution_string_braced_expansion
    ENV['RUBISH_EXECUTION_STRING'] = 'test command'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_EXECUTION_STRING} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'test command', content
  end

  def test_bash_execution_string_equals_rubish_execution_string
    ENV['RUBISH_EXECUTION_STRING'] = 'test'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_EXECUTION_STRING $RUBISH_EXECUTION_STRING > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal 2, parts.length
    assert_equal parts[0], parts[1], 'BASH_EXECUTION_STRING should equal RUBISH_EXECUTION_STRING'
  end

  # BASH_EXECUTION_STRING is read-only

  def test_bash_execution_string_assignment_ignored
    ENV['RUBISH_EXECUTION_STRING'] = 'original'
    execute('BASH_EXECUTION_STRING=modified')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_EXECUTION_STRING > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'original', content, 'BASH_EXECUTION_STRING should not be assignable'
  end

  def test_rubish_execution_string_assignment_ignored
    ENV['RUBISH_EXECUTION_STRING'] = 'original'
    execute('RUBISH_EXECUTION_STRING=modified')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_EXECUTION_STRING > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'original', content, 'RUBISH_EXECUTION_STRING should not be assignable'
  end

  # Parameter expansion

  def test_bash_execution_string_default_expansion_when_empty
    ENV.delete('RUBISH_EXECUTION_STRING')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_EXECUTION_STRING:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'default', content
  end

  def test_bash_execution_string_default_expansion_when_set
    ENV['RUBISH_EXECUTION_STRING'] = 'command'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_EXECUTION_STRING:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'command', content
  end

  def test_bash_execution_string_alternate_expansion_when_empty
    ENV.delete('RUBISH_EXECUTION_STRING')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_EXECUTION_STRING:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '', content
  end

  def test_bash_execution_string_alternate_expansion_when_set
    ENV['RUBISH_EXECUTION_STRING'] = 'command'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_EXECUTION_STRING:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content
  end

  def test_bash_execution_string_length
    ENV['RUBISH_EXECUTION_STRING'] = 'hello'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_EXECUTION_STRING} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert_equal 5, content
  end

  # BASH_EXECUTION_STRING in conditional

  def test_bash_execution_string_in_conditional_when_empty
    ENV.delete('RUBISH_EXECUTION_STRING')
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -z "$BASH_EXECUTION_STRING" ]; then echo empty; else echo set; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'empty', content
  end

  def test_bash_execution_string_in_conditional_when_set
    ENV['RUBISH_EXECUTION_STRING'] = 'command'
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -z "$BASH_EXECUTION_STRING" ]; then echo empty; else echo set; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'set', content
  end

  # BASH_EXECUTION_STRING in double quotes

  def test_bash_execution_string_in_double_quotes
    ENV['RUBISH_EXECUTION_STRING'] = 'my command'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"cmd=$BASH_EXECUTION_STRING\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'cmd=my command', content
  end
end

class TestRUBISH_EXECUTION_STRING_Alias < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_execution_string_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def test_rubish_execution_string_basic
    ENV['RUBISH_EXECUTION_STRING'] = 'echo test'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_EXECUTION_STRING > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'echo test', content
  end

  def test_rubish_execution_string_length
    ENV['RUBISH_EXECUTION_STRING'] = 'test'
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_EXECUTION_STRING} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert_equal 4, content
  end

  def test_rubish_execution_string_default_expansion
    ENV.delete('RUBISH_EXECUTION_STRING')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_EXECUTION_STRING:-fallback} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'fallback', content
  end
end
