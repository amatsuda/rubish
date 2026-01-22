# frozen_string_literal: true

require_relative 'test_helper'

class TestLocaleVariables < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_locale_test')
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

  # LANG variable tests

  def test_lang_can_be_set
    execute('LANG=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LANG']
  end

  def test_lang_can_be_exported
    execute('export LANG=ja_JP.UTF-8')
    assert_equal 'ja_JP.UTF-8', ENV['LANG']
  end

  def test_lang_can_be_read
    ENV['LANG'] = 'fr_FR.UTF-8'
    execute("echo $LANG > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'fr_FR.UTF-8', result
  end

  def test_lang_unset_is_empty
    ENV.delete('LANG')
    execute("echo \"x${LANG}x\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'xx', result
  end

  # LC_ALL variable tests

  def test_lc_all_can_be_set
    execute('LC_ALL=C')
    assert_equal 'C', ENV['LC_ALL']
  end

  def test_lc_all_can_be_exported
    execute('export LC_ALL=POSIX')
    assert_equal 'POSIX', ENV['LC_ALL']
  end

  def test_lc_all_can_be_read
    ENV['LC_ALL'] = 'en_GB.UTF-8'
    execute("echo $LC_ALL > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'en_GB.UTF-8', result
  end

  # LC_COLLATE variable tests

  def test_lc_collate_can_be_set
    execute('LC_COLLATE=C')
    assert_equal 'C', ENV['LC_COLLATE']
  end

  def test_lc_collate_can_be_exported
    execute('export LC_COLLATE=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LC_COLLATE']
  end

  def test_lc_collate_can_be_read
    ENV['LC_COLLATE'] = 'de_DE.UTF-8'
    execute("echo $LC_COLLATE > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'de_DE.UTF-8', result
  end

  # LC_CTYPE variable tests

  def test_lc_ctype_can_be_set
    execute('LC_CTYPE=C')
    assert_equal 'C', ENV['LC_CTYPE']
  end

  def test_lc_ctype_can_be_exported
    execute('export LC_CTYPE=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LC_CTYPE']
  end

  def test_lc_ctype_can_be_read
    ENV['LC_CTYPE'] = 'UTF-8'
    execute("echo $LC_CTYPE > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'UTF-8', result
  end

  # LC_MESSAGES variable tests

  def test_lc_messages_can_be_set
    execute('LC_MESSAGES=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LC_MESSAGES']
  end

  def test_lc_messages_can_be_exported
    execute('export LC_MESSAGES=C')
    assert_equal 'C', ENV['LC_MESSAGES']
  end

  def test_lc_messages_can_be_read
    ENV['LC_MESSAGES'] = 'es_ES.UTF-8'
    execute("echo $LC_MESSAGES > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'es_ES.UTF-8', result
  end

  # LC_MONETARY variable tests

  def test_lc_monetary_can_be_set
    execute('LC_MONETARY=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LC_MONETARY']
  end

  def test_lc_monetary_can_be_exported
    execute('export LC_MONETARY=de_DE.UTF-8')
    assert_equal 'de_DE.UTF-8', ENV['LC_MONETARY']
  end

  def test_lc_monetary_can_be_read
    ENV['LC_MONETARY'] = 'jp_JP.UTF-8'
    execute("echo $LC_MONETARY > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'jp_JP.UTF-8', result
  end

  # LC_NUMERIC variable tests

  def test_lc_numeric_can_be_set
    execute('LC_NUMERIC=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LC_NUMERIC']
  end

  def test_lc_numeric_can_be_exported
    execute('export LC_NUMERIC=C')
    assert_equal 'C', ENV['LC_NUMERIC']
  end

  def test_lc_numeric_can_be_read
    ENV['LC_NUMERIC'] = 'fr_FR.UTF-8'
    execute("echo $LC_NUMERIC > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'fr_FR.UTF-8', result
  end

  # LC_TIME variable tests

  def test_lc_time_can_be_set
    execute('LC_TIME=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LC_TIME']
  end

  def test_lc_time_can_be_exported
    execute('export LC_TIME=C')
    assert_equal 'C', ENV['LC_TIME']
  end

  def test_lc_time_can_be_read
    ENV['LC_TIME'] = 'de_DE.UTF-8'
    execute("echo $LC_TIME > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'de_DE.UTF-8', result
  end

  # Multiple locale variables at once

  def test_set_multiple_locale_vars
    execute('LANG=en_US.UTF-8')
    execute('LC_ALL=C')
    execute('LC_COLLATE=POSIX')
    assert_equal 'en_US.UTF-8', ENV['LANG']
    assert_equal 'C', ENV['LC_ALL']
    assert_equal 'POSIX', ENV['LC_COLLATE']
  end

  def test_export_multiple_locale_vars
    execute('export LANG=en_US.UTF-8 LC_ALL=C')
    assert_equal 'en_US.UTF-8', ENV['LANG']
    assert_equal 'C', ENV['LC_ALL']
  end

  # Unset locale variables

  def test_unset_lang
    ENV['LANG'] = 'en_US.UTF-8'
    execute('unset LANG')
    assert_nil ENV['LANG']
  end

  def test_unset_lc_all
    ENV['LC_ALL'] = 'C'
    execute('unset LC_ALL')
    assert_nil ENV['LC_ALL']
  end

  # Locale variables in subshell

  def test_lang_in_subshell
    ENV['LANG'] = 'en_US.UTF-8'
    execute("(echo $LANG) > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'en_US.UTF-8', result
  end

  # Common locale values

  def test_c_locale
    execute('LC_ALL=C')
    assert_equal 'C', get_shell_var('LC_ALL')
  end

  def test_posix_locale
    execute('LC_ALL=POSIX')
    assert_equal 'POSIX', ENV['LC_ALL']
  end

  def test_utf8_locale
    execute('LANG=en_US.UTF-8')
    assert_equal 'en_US.UTF-8', ENV['LANG']
  end

  # Edge cases

  def test_locale_with_modifier
    execute('LANG=sr_RS.UTF-8@latin')
    assert_equal 'sr_RS.UTF-8@latin', ENV['LANG']
  end

  def test_locale_with_encoding
    execute('LANG=ja_JP.eucJP')
    assert_equal 'ja_JP.eucJP', ENV['LANG']
  end

  def test_empty_locale
    execute('LANG=')
    assert_equal '', ENV['LANG']
  end
end
