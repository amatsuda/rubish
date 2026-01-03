# frozen_string_literal: true

require_relative 'test_helper'

class TestHash < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_hash_test')
    Rubish::Builtins.clear_hash
  end

  def teardown
    Rubish::Builtins.clear_hash
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test hash is a builtin
  def test_hash_is_builtin
    assert Rubish::Builtins.builtin?('hash')
  end

  # Test hash with empty table
  def test_hash_empty_table
    output = capture_output { Rubish::Builtins.run('hash', []) }
    assert_match(/hash table empty/, output)
  end

  # Test hash caches command
  def test_hash_caches_command
    Rubish::Builtins.run('hash', ['ls'])
    assert_not_nil Rubish::Builtins.hash_lookup('ls')
    assert_match(%r{/.*ls}, Rubish::Builtins.hash_lookup('ls'))
  end

  # Test hash lists cached commands
  def test_hash_lists_cached
    Rubish::Builtins.run('hash', ['ls'])
    output = capture_output { Rubish::Builtins.run('hash', []) }
    assert_match(/ls=/, output)
  end

  # Test hash -r clears table
  def test_hash_r_clears
    Rubish::Builtins.run('hash', ['ls', 'cat'])
    Rubish::Builtins.run('hash', ['-r'])
    output = capture_output { Rubish::Builtins.run('hash', []) }
    assert_match(/hash table empty/, output)
  end

  # Test hash -d forgets specific command
  def test_hash_d_forgets
    Rubish::Builtins.run('hash', ['ls', 'cat'])
    Rubish::Builtins.run('hash', ['-d', 'ls'])
    assert_nil Rubish::Builtins.hash_lookup('ls')
    assert_not_nil Rubish::Builtins.hash_lookup('cat')
  end

  # Test hash -d not found
  def test_hash_d_not_found
    output = capture_output do
      result = Rubish::Builtins.run('hash', ['-d', 'nonexistent'])
      assert_false result
    end
    assert_match(/not found/, output)
  end

  # Test hash -t prints path
  def test_hash_t_prints_path
    Rubish::Builtins.run('hash', ['ls'])
    output = capture_output { Rubish::Builtins.run('hash', ['-t', 'ls']) }
    assert_match(%r{/.*ls}, output)
  end

  # Test hash -t caches if not found
  def test_hash_t_caches_if_not_found
    output = capture_output { Rubish::Builtins.run('hash', ['-t', 'cat']) }
    assert_match(%r{/.*cat}, output)
    assert_not_nil Rubish::Builtins.hash_lookup('cat')
  end

  # Test hash -p sets custom path
  def test_hash_p_sets_path
    Rubish::Builtins.run('hash', ['-p', '/custom/path', 'mycommand'])
    assert_equal '/custom/path', Rubish::Builtins.hash_lookup('mycommand')
  end

  # Test hash -l lists in reusable format
  def test_hash_l_reusable_format
    Rubish::Builtins.run('hash', ['ls'])
    output = capture_output { Rubish::Builtins.run('hash', ['-l']) }
    assert_match(/hash -p .* ls/, output)
  end

  # Test hash not found
  def test_hash_command_not_found
    output = capture_output do
      result = Rubish::Builtins.run('hash', ['nonexistent_xyz'])
      assert_false result
    end
    assert_match(/not found/, output)
  end

  # Test hash multiple commands
  def test_hash_multiple_commands
    Rubish::Builtins.run('hash', ['ls', 'cat', 'echo'])
    assert_not_nil Rubish::Builtins.hash_lookup('ls')
    assert_not_nil Rubish::Builtins.hash_lookup('cat')
    assert_not_nil Rubish::Builtins.hash_lookup('echo')
  end

  # Test type identifies hash as builtin
  def test_type_identifies_hash_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['hash']) }
    assert_match(/hash is a shell builtin/, output)
  end

  # Test hash via REPL
  def test_hash_via_repl
    execute('hash ls')
    assert_not_nil Rubish::Builtins.hash_lookup('ls')
  end

  # Test invalid option
  def test_hash_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('hash', ['-x', 'ls'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end
end
