# frozen_string_literal: true

require_relative 'test_helper'

class TestEnable < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_enable_test')
    # Clear disabled builtins between tests
    Rubish::Builtins.disabled_builtins.clear
  end

  def teardown
    Rubish::Builtins.disabled_builtins.clear
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test enable is a builtin
  def test_enable_is_builtin
    assert Rubish::Builtins.builtin?('enable')
  end

  # Test enable lists all enabled builtins
  def test_enable_lists_enabled
    output = capture_output { Rubish::Builtins.run('enable', []) }
    assert_match(/enable cd/, output)
    assert_match(/enable echo/, output)
    assert_match(/enable pwd/, output)
    lines = output.strip.split("\n")
    assert lines.length >= 40  # Should have many builtins
  end

  # Test enable -n disables a builtin
  def test_enable_n_disables
    result = Rubish::Builtins.run('enable', ['-n', 'echo'])
    assert result
    assert Rubish::Builtins.disabled_builtins.include?('echo')
    assert_false Rubish::Builtins.builtin?('echo')
  end

  # Test enable re-enables a builtin
  def test_enable_reenables
    Rubish::Builtins.run('enable', ['-n', 'echo'])
    assert_false Rubish::Builtins.builtin?('echo')

    Rubish::Builtins.run('enable', ['echo'])
    assert Rubish::Builtins.builtin?('echo')
  end

  # Test enable -n shows disabled builtins
  def test_enable_n_lists_disabled
    Rubish::Builtins.run('enable', ['-n', 'echo'])
    Rubish::Builtins.run('enable', ['-n', 'pwd'])

    output = capture_output { Rubish::Builtins.run('enable', ['-n']) }
    assert_match(/enable -n echo/, output)
    assert_match(/enable -n pwd/, output)
  end

  # Test enable -a shows all builtins
  def test_enable_a_shows_all
    Rubish::Builtins.run('enable', ['-n', 'echo'])

    output = capture_output { Rubish::Builtins.run('enable', ['-a']) }
    assert_match(/enable -n echo/, output)
    assert_match(/enable cd/, output)
  end

  # Test enable -s shows special builtins
  def test_enable_s_shows_special
    output = capture_output { Rubish::Builtins.run('enable', ['-s']) }
    assert_match(/enable \./, output)
    assert_match(/enable :/, output)
    assert_match(/enable break/, output)
    assert_match(/enable export/, output)
  end

  # Test enable with invalid builtin name
  def test_enable_invalid_name
    output = capture_output do
      result = Rubish::Builtins.run('enable', ['nonexistent'])
      assert_false result
    end
    assert_match(/not a shell builtin/, output)
  end

  # Test enable with invalid option
  def test_enable_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('enable', ['-x'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test enable -f not supported
  def test_enable_f_not_supported
    output = capture_output do
      result = Rubish::Builtins.run('enable', ['-f', 'file'])
      assert_false result
    end
    assert_match(/not supported/, output)
  end

  # Test enable multiple builtins
  def test_enable_multiple
    result = Rubish::Builtins.run('enable', ['-n', 'echo', 'pwd', 'cd'])
    assert result
    assert_false Rubish::Builtins.builtin?('echo')
    assert_false Rubish::Builtins.builtin?('pwd')
    assert_false Rubish::Builtins.builtin?('cd')
  end

  # Test builtin_exists? helper
  def test_builtin_exists_helper
    assert Rubish::Builtins.builtin_exists?('echo')
    Rubish::Builtins.run('enable', ['-n', 'echo'])
    # Still exists, just disabled
    assert Rubish::Builtins.builtin_exists?('echo')
    assert_false Rubish::Builtins.builtin?('echo')
  end

  # Test builtin_enabled? helper
  def test_builtin_enabled_helper
    assert Rubish::Builtins.builtin_enabled?('echo')
    Rubish::Builtins.run('enable', ['-n', 'echo'])
    assert_false Rubish::Builtins.builtin_enabled?('echo')
  end

  # Test type identifies enable as builtin
  def test_type_identifies_enable_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['enable']) }
    assert_match(/enable is a shell builtin/, output)
  end

  # Test enable via REPL
  def test_enable_via_repl
    execute('enable -n echo')
    assert_false Rubish::Builtins.builtin?('echo')

    execute('enable echo')
    assert Rubish::Builtins.builtin?('echo')
  end

  # Test disabled builtin not found by type
  def test_disabled_builtin_not_found_by_type
    Rubish::Builtins.run('enable', ['-n', 'echo'])
    output = capture_output { Rubish::Builtins.run('type', ['echo']) }
    # Should find external echo command, not builtin
    assert_no_match(/shell builtin/, output)
  end
end
