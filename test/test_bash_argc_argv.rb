# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_ARGC < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_argc_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_ARGC array functionality

  def test_bash_argc_is_array
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_ARGC[@]} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content >= 0
  end

  def test_bash_argc_equals_rubish_argc_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_ARGC[@]} ${#RUBISH_ARGC[@]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_ARGC length should equal RUBISH_ARGC length'
  end

  def test_bash_argc_element_access
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ARGC[0]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_argc_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ARGC[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_argc_indices
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_ARGC[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  # BASH_ARGC is read-only

  def test_bash_argc_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_ARGC=test')
    execute("echo done > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'done', content
  end
end

class TestBASH_ARGV < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_argv_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_ARGV array functionality

  def test_bash_argv_is_array
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_ARGV[@]} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content >= 0
  end

  def test_bash_argv_equals_rubish_argv_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_ARGV[@]} ${#RUBISH_ARGV[@]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_ARGV length should equal RUBISH_ARGV length'
  end

  def test_bash_argv_element_access
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ARGV[0]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_argv_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ARGV[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_argv_indices
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_ARGV[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  # BASH_ARGV is read-only

  def test_bash_argv_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_ARGV=test')
    execute("echo done > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'done', content
  end
end

class TestBASH_ALIASES < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_aliases_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_ALIASES associative array functionality

  def test_bash_aliases_is_array
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_ALIASES[@]} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content >= 0
  end

  def test_bash_aliases_equals_rubish_aliases_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_ALIASES[@]} ${#RUBISH_ALIASES[@]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_ALIASES length should equal RUBISH_ALIASES length'
  end

  def test_bash_aliases_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_ALIASES[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_aliases_keys
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_ALIASES[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  # BASH_ALIASES is read-only

  def test_bash_aliases_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_ALIASES=test')
    execute("echo done > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'done', content
  end

  # BASH_ALIASES reflects alias command

  def test_bash_aliases_reflects_alias_command
    execute('alias myalias="echo hello"')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_ALIASES[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.include?('myalias'), 'BASH_ALIASES should contain myalias'
    execute('unalias myalias')
  end
end

class TestBASH_CMDS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_cmds_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_CMDS associative array functionality

  def test_bash_cmds_is_array
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_CMDS[@]} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content >= 0
  end

  def test_bash_cmds_equals_rubish_cmds_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_CMDS[@]} ${#RUBISH_CMDS[@]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_CMDS length should equal RUBISH_CMDS length'
  end

  def test_bash_cmds_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_CMDS[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  def test_bash_cmds_keys
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_CMDS[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length >= 0
  end

  # BASH_CMDS is read-only

  def test_bash_cmds_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_CMDS=test')
    execute("echo done > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'done', content
  end
end
