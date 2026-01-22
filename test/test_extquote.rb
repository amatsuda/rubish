# frozen_string_literal: true

require_relative 'test_helper'

class TestExtquote < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_extquote_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    @original_env = {}
    %w[testvar UNSET_VAR TEXTDOMAIN].each do |var|
      @original_env[var] = ENV[var]
    end
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    @original_env.each do |k, v|
      if v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # extquote is enabled by default
  def test_extquote_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('extquote')
  end

  def test_extquote_can_be_disabled
    execute('shopt -u extquote')
    assert_false Rubish::Builtins.shopt_enabled?('extquote')
  end

  def test_extquote_can_be_enabled
    execute('shopt -u extquote')
    execute('shopt -s extquote')
    assert Rubish::Builtins.shopt_enabled?('extquote')
  end

  # Test the option is in SHELL_OPTIONS
  def test_extquote_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('extquote')
    # SHELL_OPTIONS stores [default_value, description] arrays
    assert_equal true, Rubish::Builtins::SHELL_OPTIONS['extquote'][0] # default on
  end

  # Test $'...' ANSI-C quoting in parameter expansion with extquote enabled
  def test_ansi_c_quoting_in_default_value
    ENV.delete('UNSET_VAR')
    # ${UNSET_VAR:-$'hello\nworld'} should expand $'\n' to actual newline
    execute("echo \"${UNSET_VAR:-\$'hello\\nworld'}\" > #{output_file}")
    assert_equal "hello\nworld\n", File.read(output_file)
  end

  def test_ansi_c_quoting_tab_escape
    ENV.delete('UNSET_VAR')
    execute("echo \"${UNSET_VAR:-\$'a\\tb'}\" > #{output_file}")
    assert_equal "a\tb\n", File.read(output_file)
  end

  def test_ansi_c_quoting_backslash_escape
    ENV.delete('UNSET_VAR')
    execute("echo \"${UNSET_VAR:-\$'a\\\\b'}\" > #{output_file}")
    assert_equal "a\\b\n", File.read(output_file)
  end

  def test_ansi_c_quoting_single_quote_escape
    ENV.delete('UNSET_VAR')
    execute("echo \"${UNSET_VAR:-\$'it\\'s'}\" > #{output_file}")
    assert_equal "it's\n", File.read(output_file)
  end

  # Test $'...' NOT processed when extquote is disabled
  def test_ansi_c_quoting_disabled
    execute('shopt -u extquote')
    ENV.delete('UNSET_VAR')
    # With extquote disabled, $'...' should be treated literally
    execute("echo \"${UNSET_VAR:-\$'hello\\nworld'}\" > #{output_file}")
    # The $'...' should remain as-is
    assert_equal "$'hello\\nworld'\n", File.read(output_file)
  end

  # Test $"..." locale translation in parameter expansion
  def test_locale_string_in_default_value
    ENV.delete('UNSET_VAR')
    ENV.delete('TEXTDOMAIN')  # No translation, should return original
    execute("echo \"${UNSET_VAR:-\$\"hello\"}\" > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_locale_string_disabled
    execute('shopt -u extquote')
    ENV.delete('UNSET_VAR')
    # With extquote disabled, $"..." should be treated literally
    execute("echo \"${UNSET_VAR:-\$\"hello\"}\" > #{output_file}")
    assert_equal "$\"hello\"\n", File.read(output_file)
  end

  # Test toggle behavior
  def test_toggle_extquote
    ENV.delete('UNSET_VAR')

    # Default: enabled - $'\n' expands to newline
    execute("echo \"${UNSET_VAR:-\$'a\\nb'}\" > #{output_file}")
    assert_equal "a\nb\n", File.read(output_file)

    # Disable
    execute('shopt -u extquote')
    execute("echo \"${UNSET_VAR:-\$'a\\nb'}\" > #{output_file}")
    assert_equal "$'a\\nb'\n", File.read(output_file)

    # Re-enable
    execute('shopt -s extquote')
    execute("echo \"${UNSET_VAR:-\$'a\\nb'}\" > #{output_file}")
    assert_equal "a\nb\n", File.read(output_file)
  end

  # Test with variable set (operand not used)
  def test_extquote_with_set_variable
    ENV['testvar'] = 'existing'
    # Variable is set, so the default with $'...' is not used
    execute("echo \"${testvar:-\$'default\\nvalue'}\" > #{output_file}")
    assert_equal "existing\n", File.read(output_file)
  end

  # Test :+ operator (use value if set)
  def test_extquote_plus_operator
    ENV['testvar'] = 'set'
    execute("echo \"${testvar:+\$'was\\nset'}\" > #{output_file}")
    assert_equal "was\nset\n", File.read(output_file)
  end

  # Test := operator (assign default)
  def test_extquote_assign_operator
    ENV.delete('UNSET_VAR')
    execute("echo \"${UNSET_VAR:=\$'default\\nvalue'}\" > #{output_file}")
    assert_equal "default\nvalue\n", File.read(output_file)
    # Variable should now be set with expanded value
    assert_equal "default\nvalue", get_shell_var('UNSET_VAR')
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt extquote')
    end
    assert_match(/extquote/, output)
    assert_match(/on/, output)

    execute('shopt -u extquote')

    output = capture_output do
      execute('shopt extquote')
    end
    assert_match(/extquote/, output)
    assert_match(/off/, output)
  end

  # Test that the option is listed in shopt output
  def test_option_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/extquote/, output)
  end

  # Test shopt -q for extquote
  def test_shopt_q_extquote
    # Default is enabled, so -q should return true
    result = Rubish::Builtins.run('shopt', ['-q', 'extquote'])
    assert result

    Rubish::Builtins.run('shopt', ['-u', 'extquote'])
    result = Rubish::Builtins.run('shopt', ['-q', 'extquote'])
    assert_false result
  end

  # Test multiple escape sequences
  def test_multiple_escape_sequences
    ENV.delete('UNSET_VAR')
    execute("echo \"${UNSET_VAR:-\$'\\t\\n\\r'}\" > #{output_file}")
    assert_equal "\t\n\r\n", File.read(output_file)
  end

  # Test mixed content with $'...'
  def test_mixed_content
    ENV.delete('UNSET_VAR')
    execute("echo \"${UNSET_VAR:-prefix\$'\\n'suffix}\" > #{output_file}")
    assert_equal "prefix\nsuffix\n", File.read(output_file)
  end
end
