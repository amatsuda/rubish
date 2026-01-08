# frozen_string_literal: true

require_relative 'test_helper'

class TestExtdebug < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_extdebug_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    # Clear any existing functions
    @original_functions = @repl.functions.dup
    @repl.functions.clear
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    @repl.functions.clear
    @original_functions.each { |k, v| @repl.functions[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  # extdebug is disabled by default
  def test_extdebug_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('extdebug')
  end

  def test_extdebug_can_be_enabled
    execute('shopt -s extdebug')
    assert Rubish::Builtins.shopt_enabled?('extdebug')
  end

  def test_extdebug_can_be_disabled
    execute('shopt -s extdebug')
    execute('shopt -u extdebug')
    assert_false Rubish::Builtins.shopt_enabled?('extdebug')
  end

  # Test the option is in SHELL_OPTIONS
  def test_extdebug_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('extdebug')
    # SHELL_OPTIONS stores [default_value, description] arrays
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['extdebug'][0] # default off
  end

  # Test toggle behavior
  def test_toggle_extdebug
    # Default: disabled
    assert_false Rubish::Builtins.shopt_enabled?('extdebug')

    # Enable
    execute('shopt -s extdebug')
    assert Rubish::Builtins.shopt_enabled?('extdebug')

    # Disable
    execute('shopt -u extdebug')
    assert_false Rubish::Builtins.shopt_enabled?('extdebug')

    # Re-enable
    execute('shopt -s extdebug')
    assert Rubish::Builtins.shopt_enabled?('extdebug')
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt extdebug')
    end
    assert_match(/extdebug/, output)
    assert_match(/off/, output)

    execute('shopt -s extdebug')

    output = capture_output do
      execute('shopt extdebug')
    end
    assert_match(/extdebug/, output)
    assert_match(/on/, output)
  end

  # Test that the option is listed in shopt output
  def test_option_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/extdebug/, output)
  end

  # Test declare -F output format without extdebug
  def test_declare_F_without_extdebug
    # Define a function
    execute('myfunc() { echo hello; }')

    # Without extdebug, output shows "declare -f funcname" format
    output = capture_output do
      execute('declare -F myfunc')
    end
    assert_match(/declare -f myfunc/, output)
  end

  # Test declare -F output format with extdebug enabled
  def test_declare_F_with_extdebug
    # Set source file for testing
    @repl.instance_variable_set(:@current_source_file, '/test/script.sh')
    @repl.instance_variable_set(:@lineno, 42)

    # Define a function
    execute('testfunc() { echo test; }')

    # Enable extdebug
    execute('shopt -s extdebug')

    # With extdebug, output should be in bash format: "funcname lineno filename"
    output = capture_output do
      execute('declare -F testfunc')
    end
    # Should match format: funcname lineno filename
    assert_match(/testfunc \d+ \/test\/script\.sh/, output)
  end

  # Test declare -F with multiple functions and extdebug
  def test_declare_F_multiple_functions_extdebug
    @repl.instance_variable_set(:@current_source_file, '/scripts/lib.sh')
    @repl.instance_variable_set(:@lineno, 10)
    execute('func1() { true; }')

    @repl.instance_variable_set(:@lineno, 20)
    execute('func2() { false; }')

    execute('shopt -s extdebug')

    output = capture_output do
      execute('declare -F')
    end
    assert_match(/func1 \d+ \/scripts\/lib\.sh/, output)
    assert_match(/func2 \d+ \/scripts\/lib\.sh/, output)
  end

  # Test declare -F without source file
  def test_declare_F_no_source_file
    # No source file set (interactive mode)
    @repl.instance_variable_set(:@current_source_file, nil)
    execute('interactivefunc() { echo interactive; }')

    # Enable extdebug
    execute('shopt -s extdebug')

    # Without source file, should fall back to regular format
    output = capture_output do
      execute('declare -F interactivefunc')
    end
    assert_match(/declare -f interactivefunc/, output)
  end

  # Test shopt -q for extdebug
  def test_shopt_q_extdebug
    # Default is disabled, so -q should return false
    result = Rubish::Builtins.run('shopt', ['-q', 'extdebug'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'extdebug'])
    result = Rubish::Builtins.run('shopt', ['-q', 'extdebug'])
    assert result
  end

  # Test that function stores line number
  def test_function_stores_lineno
    @repl.instance_variable_set(:@lineno, 100)
    execute('numberedfunc() { true; }')

    func_info = @repl.functions['numberedfunc']
    assert_not_nil func_info
    assert_equal 100, func_info[:lineno]
  end

  # Test function_getter includes lineno
  def test_function_getter_includes_lineno
    @repl.instance_variable_set(:@current_source_file, '/path/to/file.sh')
    @repl.instance_variable_set(:@lineno, 55)
    execute('getterfunc() { echo getter; }')

    info = Rubish::Builtins.function_getter.call('getterfunc')
    assert_not_nil info
    assert_equal '/path/to/file.sh', info[:file]
    assert_equal 55, info[:lineno]
  end
end
