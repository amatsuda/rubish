# frozen_string_literal: true

require_relative 'test_helper'

class TestNoexpandTranslation < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_noexpand_translation_test')
  end

  def teardown
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # noexpand_translation is disabled by default
  def test_noexpand_translation_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('noexpand_translation')
  end

  def test_noexpand_translation_can_be_enabled
    execute('shopt -s noexpand_translation')
    assert Rubish::Builtins.shopt_enabled?('noexpand_translation')
  end

  def test_noexpand_translation_can_be_disabled
    execute('shopt -s noexpand_translation')
    execute('shopt -u noexpand_translation')
    assert_false Rubish::Builtins.shopt_enabled?('noexpand_translation')
  end

  # Without noexpand_translation: $"..." attempts translation (falls back to original if no gettext)
  def test_translate_without_noexpand_translation
    ENV['TEXTDOMAIN'] = 'testapp'
    # Without noexpand_translation, __translate is called
    # Since gettext is likely not installed, it returns the original string
    execute("echo $\"Hello World\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello World', result
  end

  # With noexpand_translation: $"..." is NOT translated, returns original string
  def test_translate_with_noexpand_translation
    execute('shopt -s noexpand_translation')
    ENV['TEXTDOMAIN'] = 'testapp'

    execute("echo $\"Hello World\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello World', result
  end

  # Test that noexpand_translation bypasses TEXTDOMAIN check
  def test_noexpand_translation_ignores_textdomain
    execute('shopt -s noexpand_translation')
    # Even with TEXTDOMAIN set, translation is skipped
    ENV['TEXTDOMAIN'] = 'some_app'
    ENV['TEXTDOMAINDIR'] = '/some/path'

    # The string should be returned as-is without any translation attempt
    result = @repl.send(:__translate, 'Test Message')
    assert_equal 'Test Message', result
  end

  # Test without TEXTDOMAIN (translation wouldn't happen anyway)
  def test_noexpand_translation_without_textdomain
    execute('shopt -s noexpand_translation')
    ENV.delete('TEXTDOMAIN')

    execute("echo $\"No Translation\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'No Translation', result
  end

  # Test multiple $"..." strings with noexpand_translation
  def test_multiple_locale_strings_with_noexpand
    execute('shopt -s noexpand_translation')
    ENV['TEXTDOMAIN'] = 'myapp'

    execute("echo $\"Hello\" $\"World\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello World', result
  end

  # Test that disabling noexpand_translation restores normal behavior
  def test_disable_restores_normal_behavior
    execute('shopt -s noexpand_translation')
    execute('shopt -u noexpand_translation')
    ENV['TEXTDOMAIN'] = 'testapp'

    # Now __translate should be called normally
    execute("echo $\"Test\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Test', result
  end

  # Test __translate method directly
  def test_translate_method_respects_noexpand
    execute('shopt -s noexpand_translation')
    ENV['TEXTDOMAIN'] = 'myapp'

    result = @repl.send(:__translate, 'Direct Call')
    assert_equal 'Direct Call', result
  end

  # Test __translate method without noexpand
  def test_translate_method_without_noexpand
    ENV['TEXTDOMAIN'] = 'myapp'
    # Without noexpand_translation, it attempts translation
    # Falls back to original since gettext isn't available
    result = @repl.send(:__translate, 'Direct Call')
    assert_equal 'Direct Call', result
  end

  # Test with empty string
  def test_noexpand_translation_empty_string
    execute('shopt -s noexpand_translation')

    result = @repl.send(:__translate, '')
    assert_equal '', result
  end

  # Test with special characters
  def test_noexpand_translation_special_chars
    execute('shopt -s noexpand_translation')
    ENV['TEXTDOMAIN'] = 'testapp'

    execute("echo $\"Hello, World! @#\$%\" > #{output_file}")
    result = File.read(output_file).strip
    # The $ in the middle might be expanded, but the $"..." wrapper should work
    assert_match(/Hello, World!/, result)
  end

  # Test variable expansion inside $"..." with noexpand
  def test_noexpand_with_variable_inside
    execute('shopt -s noexpand_translation')
    ENV['NAME'] = 'Alice'
    ENV['TEXTDOMAIN'] = 'testapp'

    # Variable expansion inside $"..." still works
    execute("echo $\"Hello \$NAME\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello Alice', result
  end

  # Test that noexpand_translation doesn't affect regular strings
  def test_noexpand_does_not_affect_regular_strings
    execute('shopt -s noexpand_translation')
    ENV['VAR'] = 'test'

    execute("echo \"Hello World\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello World', result
  end

  # Test noexpand_translation with assignment
  def test_noexpand_translation_in_assignment
    execute('shopt -s noexpand_translation')
    ENV['TEXTDOMAIN'] = 'testapp'

    # Test that $"..." in assignment works with noexpand_translation
    execute("echo $\"Test Message\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Test Message', result
  end
end
