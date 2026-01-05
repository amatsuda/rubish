# frozen_string_literal: true

require_relative 'test_helper'

class TestTextdomain < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_textdomain_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # TEXTDOMAIN variable tests

  def test_textdomain_can_be_set
    execute('TEXTDOMAIN=myapp')
    assert_equal 'myapp', ENV['TEXTDOMAIN']
  end

  def test_textdomain_can_be_exported
    execute('export TEXTDOMAIN=myapp')
    assert_equal 'myapp', ENV['TEXTDOMAIN']
  end

  def test_textdomain_can_be_read
    ENV['TEXTDOMAIN'] = 'testapp'
    execute("echo $TEXTDOMAIN > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'testapp', result
  end

  def test_textdomain_unset_is_empty
    ENV.delete('TEXTDOMAIN')
    execute("echo \"x${TEXTDOMAIN}x\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'xx', result
  end

  # TEXTDOMAINDIR variable tests

  def test_textdomaindir_can_be_set
    execute('TEXTDOMAINDIR=/usr/share/locale')
    assert_equal '/usr/share/locale', ENV['TEXTDOMAINDIR']
  end

  def test_textdomaindir_can_be_exported
    execute('export TEXTDOMAINDIR=/opt/locale')
    assert_equal '/opt/locale', ENV['TEXTDOMAINDIR']
  end

  def test_textdomaindir_can_be_read
    ENV['TEXTDOMAINDIR'] = '/custom/locale'
    execute("echo $TEXTDOMAINDIR > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '/custom/locale', result
  end

  def test_textdomaindir_unset_is_empty
    ENV.delete('TEXTDOMAINDIR')
    execute("echo \"x${TEXTDOMAINDIR}x\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'xx', result
  end

  # $"..." locale string tests

  def test_locale_string_without_textdomain_returns_original
    ENV.delete('TEXTDOMAIN')
    execute("echo $\"Hello World\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello World', result
  end

  def test_locale_string_with_empty_textdomain_returns_original
    ENV['TEXTDOMAIN'] = ''
    execute("echo $\"Hello World\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello World', result
  end

  def test_locale_string_returns_original_without_gettext
    # Without the gettext gem, should return original string
    ENV['TEXTDOMAIN'] = 'myapp'
    execute("echo $\"Hello World\" > #{output_file}")
    result = File.read(output_file).strip
    # Either translated or original (depending on gettext availability)
    assert_match(/Hello World/, result)
  end

  def test_locale_string_with_variable
    ENV.delete('TEXTDOMAIN')
    ENV['NAME'] = 'Alice'
    execute("echo $\"Hello $NAME\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello Alice', result
  end

  def test_locale_string_with_escape
    ENV.delete('TEXTDOMAIN')
    execute("echo $\"Hello\\tWorld\" > #{output_file}")
    result = File.read(output_file).strip
    # The escape sequence should be preserved
    assert_match(/Hello.*World/, result)
  end

  def test_locale_string_multiple_in_line
    ENV.delete('TEXTDOMAIN')
    execute("echo $\"Hello\" $\"World\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'Hello World', result
  end

  # Both variables together

  def test_both_variables_can_be_set
    execute('TEXTDOMAIN=myapp')
    execute('TEXTDOMAINDIR=/usr/share/locale')
    assert_equal 'myapp', ENV['TEXTDOMAIN']
    assert_equal '/usr/share/locale', ENV['TEXTDOMAINDIR']
  end

  def test_export_both_variables
    execute('export TEXTDOMAIN=myapp TEXTDOMAINDIR=/opt/locale')
    assert_equal 'myapp', ENV['TEXTDOMAIN']
    assert_equal '/opt/locale', ENV['TEXTDOMAINDIR']
  end

  # Integration with __translate method

  def test_translate_returns_original_when_no_textdomain
    ENV.delete('TEXTDOMAIN')
    result = @repl.send(:__translate, 'Hello')
    assert_equal 'Hello', result
  end

  def test_translate_returns_original_when_empty_textdomain
    ENV['TEXTDOMAIN'] = ''
    result = @repl.send(:__translate, 'Hello')
    assert_equal 'Hello', result
  end

  def test_translate_with_textdomain_set
    ENV['TEXTDOMAIN'] = 'testapp'
    # Without gettext gem, should still return original
    result = @repl.send(:__translate, 'Hello')
    assert_equal 'Hello', result
  end

  def test_translate_preserves_special_characters
    ENV.delete('TEXTDOMAIN')
    result = @repl.send(:__translate, 'Hello, World!')
    assert_equal 'Hello, World!', result
  end

  def test_translate_preserves_unicode
    ENV.delete('TEXTDOMAIN')
    result = @repl.send(:__translate, '你好世界')
    assert_equal '你好世界', result
  end
end
