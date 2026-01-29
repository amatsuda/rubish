# frozen_string_literal: true

require_relative 'test_helper'

class TestTRAPSIG < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('trapsig_test')
    Dir.chdir(@tempdir)
    # Clear any existing traps
    Rubish::Builtins.traps.clear
    Rubish::Builtins.current_trapsig = ''
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.traps.clear
    Rubish::Builtins.current_trapsig = ''
  end

  # Basic RUBISH_TRAPSIG functionality

  def test_rubish_trapsig_empty_outside_trap
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_TRAPSIG}x\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'xx', content, 'RUBISH_TRAPSIG should be empty outside of trap handler'
  end

  def test_bash_trapsig_empty_outside_trap
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${BASH_TRAPSIG}x\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'xx', content, 'BASH_TRAPSIG should be empty outside of trap handler'
  end

  def test_bash_trapsig_equals_rubish_trapsig
    # Both should return empty outside of trap
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"${RUBISH_TRAPSIG}\" \"${BASH_TRAPSIG}\" > #{output_file}")
    content = File.read(output_file).strip
    # Should be empty, resulting in just space
    assert_equal '', content.strip, 'Both TRAPSIG variables should be equal'
  end

  # TRAPSIG in EXIT trap

  def test_rubish_trapsig_in_exit_trap
    output_file = File.join(@tempdir, 'exit_output.txt')
    # Set up EXIT trap that records the signal name
    Rubish::Builtins.traps[0] = "echo $RUBISH_TRAPSIG > #{output_file}"
    Rubish::Builtins.exit_traps
    content = File.read(output_file).strip
    assert_equal 'EXIT', content, 'RUBISH_TRAPSIG should be EXIT in exit trap'
  end

  def test_bash_trapsig_in_exit_trap
    output_file = File.join(@tempdir, 'exit_output.txt')
    Rubish::Builtins.traps[0] = "echo $BASH_TRAPSIG > #{output_file}"
    Rubish::Builtins.exit_traps
    content = File.read(output_file).strip
    assert_equal 'EXIT', content, 'BASH_TRAPSIG should be EXIT in exit trap'
  end

  # TRAPSIG in ERR trap

  def test_rubish_trapsig_in_err_trap
    output_file = File.join(@tempdir, 'err_output.txt')
    Rubish::Builtins.traps['ERR'] = "echo $RUBISH_TRAPSIG > #{output_file}"
    Rubish::Builtins.err_trap
    content = File.read(output_file).strip
    assert_equal 'ERR', content, 'RUBISH_TRAPSIG should be ERR in err trap'
  end

  def test_bash_trapsig_in_err_trap
    output_file = File.join(@tempdir, 'err_output.txt')
    Rubish::Builtins.traps['ERR'] = "echo $BASH_TRAPSIG > #{output_file}"
    Rubish::Builtins.err_trap
    content = File.read(output_file).strip
    assert_equal 'ERR', content, 'BASH_TRAPSIG should be ERR in err trap'
  end

  # TRAPSIG in DEBUG trap

  def test_rubish_trapsig_in_debug_trap
    output_file = File.join(@tempdir, 'debug_output.txt')
    Rubish::Builtins.traps['DEBUG'] = "echo $RUBISH_TRAPSIG > #{output_file}"
    Rubish::Builtins.debug_trap
    content = File.read(output_file).strip
    assert_equal 'DEBUG', content, 'RUBISH_TRAPSIG should be DEBUG in debug trap'
  end

  # TRAPSIG in RETURN trap

  def test_rubish_trapsig_in_return_trap
    output_file = File.join(@tempdir, 'return_output.txt')
    Rubish::Builtins.traps['RETURN'] = "echo $RUBISH_TRAPSIG > #{output_file}"
    Rubish::Builtins.return_trap
    content = File.read(output_file).strip
    assert_equal 'RETURN', content, 'RUBISH_TRAPSIG should be RETURN in return trap'
  end

  # TRAPSIG is read-only

  def test_rubish_trapsig_is_read_only
    execute('RUBISH_TRAPSIG=test')
    value = Rubish::Builtins.current_trapsig
    assert_equal '', value, 'RUBISH_TRAPSIG should be read-only'
  end

  def test_bash_trapsig_is_read_only
    execute('BASH_TRAPSIG=test')
    value = Rubish::Builtins.current_trapsig
    assert_equal '', value, 'BASH_TRAPSIG should be read-only'
  end

  # TRAPSIG cleared after trap completes

  def test_trapsig_cleared_after_exit_trap
    output_file = File.join(@tempdir, 'exit_output.txt')
    Rubish::Builtins.traps[0] = "echo $RUBISH_TRAPSIG > #{output_file}"
    Rubish::Builtins.exit_traps
    # After trap completes, TRAPSIG should be empty
    assert_equal '', Rubish::Builtins.current_trapsig, 'TRAPSIG should be cleared after trap'
  end

  def test_trapsig_cleared_after_err_trap
    output_file = File.join(@tempdir, 'err_output.txt')
    Rubish::Builtins.traps['ERR'] = "echo $RUBISH_TRAPSIG > #{output_file}"
    Rubish::Builtins.err_trap
    assert_equal '', Rubish::Builtins.current_trapsig, 'TRAPSIG should be cleared after trap'
  end

  # Parameter expansion

  def test_rubish_trapsig_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_TRAPSIG:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'default', content, 'RUBISH_TRAPSIG should use default when empty'
  end

  def test_rubish_trapsig_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_TRAPSIG:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '', content, 'RUBISH_TRAPSIG alternate should be empty when unset'
  end

  def test_rubish_trapsig_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_TRAPSIG} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert_equal 0, content, 'RUBISH_TRAPSIG length should be 0 when empty'
  end
end
