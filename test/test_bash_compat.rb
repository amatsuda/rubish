# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_COMPAT < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_bash_compat_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    # Clear any existing compat settings
    Rubish::Builtins.clear_compat_level
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Default state (no compat level set)

  def test_bash_compat_empty_by_default
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${BASH_COMPAT}x\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'xx', content, 'BASH_COMPAT should be empty by default'
  end

  def test_bash_compat_returns_empty_string_when_no_compat
    value = Rubish::Builtins.bash_compat
    assert_equal '', value
  end

  # Setting BASH_COMPAT with decimal format (e.g., "5.1")

  def test_bash_compat_set_decimal_format
    execute('BASH_COMPAT=5.1')
    assert Rubish::Builtins.shopt_enabled?('compat51')
  end

  def test_bash_compat_set_decimal_format_42
    execute('BASH_COMPAT=4.2')
    assert Rubish::Builtins.shopt_enabled?('compat42')
  end

  def test_bash_compat_set_decimal_format_50
    execute('BASH_COMPAT=5.0')
    assert Rubish::Builtins.shopt_enabled?('compat50')
  end

  def test_bash_compat_set_decimal_format_53
    execute('BASH_COMPAT=5.3')
    assert Rubish::Builtins.shopt_enabled?('compat53')
  end

  # Setting BASH_COMPAT with integer format (e.g., "51")

  def test_bash_compat_set_integer_format
    execute('BASH_COMPAT=51')
    assert Rubish::Builtins.shopt_enabled?('compat51')
  end

  def test_bash_compat_set_integer_format_42
    execute('BASH_COMPAT=42')
    assert Rubish::Builtins.shopt_enabled?('compat42')
  end

  def test_bash_compat_set_integer_format_31
    execute('BASH_COMPAT=31')
    assert Rubish::Builtins.shopt_enabled?('compat31')
  end

  # Reading BASH_COMPAT after setting

  def test_bash_compat_read_after_set_decimal
    execute('BASH_COMPAT=5.2')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_COMPAT > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '5.2', content
  end

  def test_bash_compat_read_after_set_integer
    execute('BASH_COMPAT=43')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_COMPAT > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '4.3', content
  end

  # Clearing BASH_COMPAT

  def test_bash_compat_clear_with_empty_string
    execute('BASH_COMPAT=5.1')
    assert Rubish::Builtins.shopt_enabled?('compat51')

    execute('BASH_COMPAT=')
    assert_false Rubish::Builtins.shopt_enabled?('compat51')

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${BASH_COMPAT}x\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'xx', content
  end

  # Invalid values

  def test_bash_compat_invalid_value_clears_compat
    execute('BASH_COMPAT=5.1')
    assert Rubish::Builtins.shopt_enabled?('compat51')

    # Setting invalid value should clear compat level
    stderr_output = capture_stderr do
      execute('BASH_COMPAT=99')
    end
    assert_match(/invalid value/, stderr_output)
    assert_false Rubish::Builtins.shopt_enabled?('compat51')
  end

  # BASH_COMPAT disables other compat options (mutual exclusivity)

  def test_bash_compat_disables_other_compat_options
    execute('shopt -s compat42')
    assert Rubish::Builtins.shopt_enabled?('compat42')

    execute('BASH_COMPAT=5.1')
    assert Rubish::Builtins.shopt_enabled?('compat51')
    assert_false Rubish::Builtins.shopt_enabled?('compat42')
  end

  def test_bash_compat_multiple_changes
    execute('BASH_COMPAT=4.2')
    assert Rubish::Builtins.shopt_enabled?('compat42')

    execute('BASH_COMPAT=5.0')
    assert Rubish::Builtins.shopt_enabled?('compat50')
    assert_false Rubish::Builtins.shopt_enabled?('compat42')

    execute('BASH_COMPAT=5.3')
    assert Rubish::Builtins.shopt_enabled?('compat53')
    assert_false Rubish::Builtins.shopt_enabled?('compat50')
  end

  # shopt also affects BASH_COMPAT

  def test_shopt_affects_bash_compat
    execute('shopt -s compat44')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_COMPAT > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '4.4', content
  end

  # Parameter expansion

  def test_bash_compat_default_expansion_when_empty
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_COMPAT:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'default', content
  end

  def test_bash_compat_default_expansion_when_set
    execute('BASH_COMPAT=5.1')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_COMPAT:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '5.1', content
  end

  def test_bash_compat_alternate_expansion_when_empty
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_COMPAT:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '', content
  end

  def test_bash_compat_alternate_expansion_when_set
    execute('BASH_COMPAT=5.1')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_COMPAT:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content
  end

  # BASH_COMPAT in conditional

  def test_bash_compat_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -z "$BASH_COMPAT" ]; then echo empty; else echo set; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'empty', content

    execute('BASH_COMPAT=5.1')
    execute('if [ -z "$BASH_COMPAT" ]; then echo empty; else echo set; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'set', content
  end

  # All valid compat levels

  def test_all_valid_compat_levels
    valid_levels = %w[3.1 3.2 4.0 4.1 4.2 4.3 4.4 5.0 5.1 5.2 5.3]
    valid_levels.each do |level|
      Rubish::Builtins.clear_compat_level
      execute("BASH_COMPAT=#{level}")
      compat_opt = "compat#{level.delete('.')}"
      assert Rubish::Builtins.shopt_enabled?(compat_opt), "Expected #{compat_opt} to be enabled for BASH_COMPAT=#{level}"
    end
  end

  # compat10 is rubish-specific

  def test_compat10_via_bash_compat
    execute('BASH_COMPAT=1.0')
    assert Rubish::Builtins.shopt_enabled?('compat10')
  end
end
