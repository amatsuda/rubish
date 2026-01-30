# frozen_string_literal: true

require_relative 'test_helper'

class TestPromptvars < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_promptvars_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    @original_ps1 = ENV['PS1']
    @original_user = ENV['USER']
    @original_env = {}
    %w[MYVAR VAR1 VAR2 EMPTYVAR UNDEFINED_VAR MYDIR TESTVAR SPECIAL SUFFIX].each do |var|
      @original_env[var] = ENV[var]
    end
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
    ENV['PS1'] = @original_ps1
    ENV['USER'] = @original_user
    @original_env.each do |k, v|
      if v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
  end

  def expand_prompt(ps)
    @repl.send(:expand_prompt, ps)
  end

  # promptvars is enabled by default
  def test_promptvars_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('promptvars')
  end

  def test_promptvars_can_be_disabled
    execute('shopt -u promptvars')
    assert_false Rubish::Builtins.shopt_enabled?('promptvars')
  end

  def test_promptvars_can_be_enabled
    execute('shopt -u promptvars')
    execute('shopt -s promptvars')
    assert Rubish::Builtins.shopt_enabled?('promptvars')
  end

  # Test variable expansion in prompt with promptvars enabled
  def test_expand_variable_in_prompt
    ENV['MYVAR'] = 'hello'
    result = expand_prompt('prefix $MYVAR suffix')
    assert_equal 'prefix hello suffix', result
  end

  def test_expand_braced_variable_in_prompt
    ENV['MYVAR'] = 'world'
    result = expand_prompt('${MYVAR}!')
    assert_equal 'world!', result
  end

  def test_expand_multiple_variables_in_prompt
    ENV['VAR1'] = 'foo'
    ENV['VAR2'] = 'bar'
    result = expand_prompt('$VAR1 and $VAR2')
    assert_equal 'foo and bar', result
  end

  # Test command substitution in prompt
  def test_command_substitution_in_prompt
    result = expand_prompt('$(echo test)')
    assert_equal 'test', result
  end

  def test_backtick_substitution_in_prompt
    result = expand_prompt('`echo hello`')
    assert_equal 'hello', result
  end

  # Test arithmetic expansion in prompt
  def test_arithmetic_expansion_in_prompt
    result = expand_prompt('$((2+3))')
    assert_equal '5', result
  end

  # Test with promptvars disabled - variables should NOT be expanded
  def test_no_variable_expansion_when_disabled
    execute('shopt -u promptvars')
    ENV['MYVAR'] = 'hello'
    result = expand_prompt('$MYVAR')
    assert_equal '$MYVAR', result
  end

  def test_no_command_substitution_when_disabled
    execute('shopt -u promptvars')
    result = expand_prompt('$(echo test)')
    assert_equal '$(echo test)', result
  end

  def test_no_backtick_substitution_when_disabled
    execute('shopt -u promptvars')
    result = expand_prompt('`echo hello`')
    assert_equal '`echo hello`', result
  end

  def test_no_arithmetic_expansion_when_disabled
    execute('shopt -u promptvars')
    result = expand_prompt('$((2+3))')
    assert_equal '$((2+3))', result
  end

  # Test combination of bash escapes and variable expansion
  def test_bash_escapes_and_variables
    ENV['MYDIR'] = '/custom'
    # \s expands to shell name, $MYDIR expands to variable
    result = expand_prompt('\\s:$MYDIR>')
    assert_match(/rubish:\/custom>/, result)
  end

  # Test that bash escapes are processed before variable expansion
  def test_bash_escapes_processed_first
    ENV['USER'] = 'testuser'
    # \u should expand to USER env var, not be treated as $u
    result = expand_prompt('\\u@\\h')
    # \u uses ENV['USER'] or Etc.getlogin
    assert_match(/testuser@/, result)
  end

  # Test toggle behavior
  def test_toggle_promptvars
    ENV['TESTVAR'] = 'expanded'

    # Default: enabled
    result1 = expand_prompt('$TESTVAR')
    assert_equal 'expanded', result1

    # Disable
    execute('shopt -u promptvars')
    result2 = expand_prompt('$TESTVAR')
    assert_equal '$TESTVAR', result2

    # Re-enable
    execute('shopt -s promptvars')
    result3 = expand_prompt('$TESTVAR')
    assert_equal 'expanded', result3
  end

  # Test empty variable
  def test_empty_variable
    ENV['EMPTYVAR'] = ''
    result = expand_prompt('before${EMPTYVAR}after')
    assert_equal 'beforeafter', result
  end

  # Test undefined variable
  def test_undefined_variable
    ENV.delete('UNDEFINED_VAR')
    result = expand_prompt('$UNDEFINED_VAR')
    assert_equal '', result
  end

  # Test nested command substitution
  def test_nested_command_substitution
    result = expand_prompt('$(echo $(echo nested))')
    assert_equal 'nested', result
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt promptvars')
    end
    assert_match(/promptvars/, output)
    assert_match(/on/, output)

    execute('shopt -u promptvars')

    output = capture_output do
      execute('shopt promptvars')
    end
    assert_match(/promptvars/, output)
    assert_match(/off/, output)
  end

  # Test with special characters
  def test_special_characters_in_variable
    ENV['SPECIAL'] = 'hello world'
    result = expand_prompt('[${SPECIAL}]')
    assert_equal '[hello world]', result
  end

  # Test that prompt escapes combined with promptvars work correctly
  def test_combined_prompt_escapes_and_vars
    ENV['SUFFIX'] = '>'
    # \$ expands to $ or # based on uid, then variable $SUFFIX should expand
    # Use space to separate them to avoid $$ being interpreted as PID
    result = expand_prompt('prompt\\$ $SUFFIX')
    # For non-root user, \$ becomes $
    assert_match(/prompt\$ >/, result)
  end
end
