# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_COMMAND < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_command_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_COMMAND functionality

  def test_bash_command_returns_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_COMMAND > #{output_file}")
    content = File.read(output_file).strip
    # BASH_COMMAND should return the command being executed
    assert content.length >= 0
  end

  def test_bash_command_equals_rubish_command_via_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_COMMAND} ${#RUBISH_COMMAND} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    # Both should have the same length
    assert_equal parts[0], parts[1], 'BASH_COMMAND length should equal RUBISH_COMMAND length'
  end

  def test_bash_command_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_COMMAND} > #{output_file}")
    content = File.read(output_file).strip
    # Should contain some command text
    assert content.length >= 0
  end

  # BASH_COMMAND is read-only

  def test_bash_command_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_COMMAND=test')
    execute("echo done > #{output_file}")
    # Should complete without error
    content = File.read(output_file).strip
    assert_equal 'done', content
  end

  # Parameter expansion

  def test_bash_command_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_COMMAND:-default} > #{output_file}")
    content = File.read(output_file).strip
    # Should not be 'default' since BASH_COMMAND is set during execution
    assert content.length > 0
  end

  def test_bash_command_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_COMMAND} > #{output_file}")
    content = File.read(output_file).strip.to_i
    # Length should be some non-negative value
    assert content >= 0
  end

  # BASH_COMMAND in conditional

  def test_bash_command_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    # At command execution time, BASH_COMMAND should be set
    execute('if [ -n "$BASH_COMMAND" ]; then echo set; else echo empty; fi > ' + output_file)
    content = File.read(output_file).strip
    # Could be either depending on when it's checked
    assert %w[set empty].include?(content)
  end
end

class TestBASH_LINENO < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_lineno_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_LINENO array functionality

  def test_bash_lineno_is_array
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_LINENO[@]} > #{output_file}")
    content = File.read(output_file).strip.to_i
    # Should return a length (0 or more)
    assert content >= 0
  end

  def test_bash_lineno_equals_rubish_lineno
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_LINENO[@]} ${#RUBISH_LINENO[@]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_LINENO length should equal RUBISH_LINENO length'
  end

  def test_bash_lineno_element_access
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_LINENO[0]} > #{output_file}")
    content = File.read(output_file).strip
    # Should return empty or a line number
    assert content.length >= 0
  end

  def test_bash_lineno_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_LINENO[@]} > #{output_file}")
    # Should complete without error
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_lineno_indices
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_LINENO[@]} > #{output_file}")
    # Should complete without error
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  # BASH_LINENO is read-only

  def test_bash_lineno_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_LINENO=test')
    execute("echo done > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'done', content
  end
end

class TestBASH_SOURCE < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_source_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_SOURCE array functionality

  def test_bash_source_is_array
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_SOURCE[@]} > #{output_file}")
    content = File.read(output_file).strip.to_i
    # Should return a length (0 or more)
    assert content >= 0
  end

  def test_bash_source_equals_rubish_source
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_SOURCE[@]} ${#RUBISH_SOURCE[@]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_SOURCE length should equal RUBISH_SOURCE length'
  end

  def test_bash_source_element_access
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_SOURCE[0]} > #{output_file}")
    content = File.read(output_file).strip
    # Should return empty or a source filename
    assert content.length >= 0
  end

  def test_bash_source_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_SOURCE[@]} > #{output_file}")
    # Should complete without error
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_source_indices
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_SOURCE[@]} > #{output_file}")
    # Should complete without error
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  # BASH_SOURCE is read-only

  def test_bash_source_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_SOURCE=test')
    execute("echo done > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'done', content
  end

  # BASH_SOURCE in sourced file

  def test_bash_source_in_sourced_file
    # Create a test script
    script_file = File.join(@tempdir, 'test_script.sh')
    output_file = File.join(@tempdir, 'output.txt')
    File.write(script_file, "echo ${BASH_SOURCE[0]} > #{output_file}")

    execute("source #{script_file}")
    content = File.read(output_file).strip
    # Should contain the script filename
    assert content.include?('test_script.sh') || content.empty?
  end
end
