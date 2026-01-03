# frozen_string_literal: true

require_relative 'test_helper'

class TestUmask < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_umask_test')
    @original_umask = File.umask
  end

  def teardown
    File.umask(@original_umask)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test umask is a builtin
  def test_umask_is_builtin
    assert Rubish::Builtins.builtin?('umask')
  end

  # Test umask displays current value
  def test_umask_display
    File.umask(0o022)
    output = capture_output { Rubish::Builtins.run('umask', []) }
    assert_equal "0022\n", output
  end

  # Test umask -S displays symbolic
  def test_umask_symbolic_display
    File.umask(0o022)
    output = capture_output { Rubish::Builtins.run('umask', ['-S']) }
    assert_equal "u=rwx,g=rx,o=rx\n", output
  end

  # Test umask -p displays reusable form
  def test_umask_reusable_display
    File.umask(0o022)
    output = capture_output { Rubish::Builtins.run('umask', ['-p']) }
    assert_equal "umask 0022\n", output
  end

  # Test umask -p -S displays symbolic reusable form
  def test_umask_symbolic_reusable_display
    File.umask(0o022)
    output = capture_output { Rubish::Builtins.run('umask', ['-p', '-S']) }
    assert_equal "umask -S u=rwx,g=rx,o=rx\n", output
  end

  # Test setting umask with octal
  def test_umask_set_octal
    Rubish::Builtins.run('umask', ['0077'])
    assert_equal 0o077, File.umask
  end

  def test_umask_set_octal_three_digits
    Rubish::Builtins.run('umask', ['077'])
    assert_equal 0o077, File.umask
  end

  # Test setting umask with symbolic mode
  def test_umask_set_symbolic_equals
    File.umask(0o000)
    Rubish::Builtins.run('umask', ['u=rx,g=rx,o=rx'])
    # u=rx means no w, so umask should have w bit set for u
    # rx = 5, rwx = 7, so mask = 7-5 = 2 for each
    assert_equal 0o222, File.umask
  end

  def test_umask_set_symbolic_minus
    File.umask(0o000)  # All permissions
    Rubish::Builtins.run('umask', ['o-w'])
    # Remove write from others means umask gets w bit for others
    assert_equal 0o002, File.umask
  end

  def test_umask_set_symbolic_plus
    File.umask(0o077)  # No permissions for group/other
    Rubish::Builtins.run('umask', ['go+r'])
    # Add read to group/others means umask loses r bit
    # 077 = ---rwxrwx (no perms for g/o)
    # go+r means g=r,o=r permissions
    # New perms: u=rwx, g=r, o=r = 744, mask = 033
    assert_equal 0o033, File.umask
  end

  # Test invalid mode
  def test_umask_invalid_mode
    output = capture_output do
      result = Rubish::Builtins.run('umask', ['invalid'])
      assert_false result
    end
    assert_match(/invalid mode/, output)
  end

  # Test type identifies umask as builtin
  def test_type_identifies_umask_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['umask']) }
    assert_match(/umask is a shell builtin/, output)
  end

  # Test via REPL
  def test_umask_via_repl
    execute('umask 0027')
    assert_equal 0o027, File.umask
  end

  # Test umask affects file creation
  def test_umask_affects_file_creation
    File.umask(0o077)
    test_file = File.join(@tempdir, 'test.txt')
    File.write(test_file, 'test')
    mode = File.stat(test_file).mode & 0o777
    # With umask 077, file should be 600 (rw-------)
    assert_equal 0o600, mode
  end
end
