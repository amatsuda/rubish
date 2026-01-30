# frozen_string_literal: true

require_relative 'test_helper'

class TestPatsubReplacement < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_patsub_replacement_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # patsub_replacement is enabled by default
  def test_patsub_replacement_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('patsub_replacement')
  end

  def test_patsub_replacement_can_be_disabled
    execute('shopt -u patsub_replacement')
    assert_false Rubish::Builtins.shopt_enabled?('patsub_replacement')
  end

  def test_patsub_replacement_can_be_enabled
    execute('shopt -u patsub_replacement')
    execute('shopt -s patsub_replacement')
    assert Rubish::Builtins.shopt_enabled?('patsub_replacement')
  end

  # Test basic & replacement with patsub_replacement enabled
  def test_ampersand_replaced_with_match
    ENV['testvar'] = 'hello world'
    execute("echo ${testvar/hello/[&]} > #{output_file}")
    assert_equal "[hello] world\n", File.read(output_file)
  end

  def test_ampersand_replaced_in_global_substitution
    ENV['testvar'] = 'aaa bbb ccc'
    execute("echo ${testvar//a/(&)} > #{output_file}")
    assert_equal "(a)(a)(a) bbb ccc\n", File.read(output_file)
  end

  def test_multiple_ampersands_in_replacement
    ENV['testvar'] = 'foo bar'
    execute("echo ${testvar/foo/&-&-&} > #{output_file}")
    assert_equal "foo-foo-foo bar\n", File.read(output_file)
  end

  def test_ampersand_with_pattern_match
    ENV['testvar'] = 'file.txt'
    execute("echo ${testvar/*.txt/&.bak} > #{output_file}")
    assert_equal "file.txt.bak\n", File.read(output_file)
  end

  # Test escaped & (literal)
  def test_escaped_ampersand_is_literal
    ENV['testvar'] = 'hello world'
    execute("echo ${testvar/hello/\\&} > #{output_file}")
    assert_equal "& world\n", File.read(output_file)
  end

  def test_mixed_escaped_and_unescaped_ampersand
    ENV['testvar'] = 'foo bar'
    execute("echo ${testvar/foo/&\\&&} > #{output_file}")
    assert_equal "foo&foo bar\n", File.read(output_file)
  end

  # Test with patsub_replacement disabled
  def test_ampersand_literal_when_disabled
    execute('shopt -u patsub_replacement')
    ENV['testvar'] = 'hello world'
    execute("echo ${testvar/hello/[&]} > #{output_file}")
    assert_equal "[&] world\n", File.read(output_file)
  end

  def test_ampersand_literal_in_global_when_disabled
    execute('shopt -u patsub_replacement')
    ENV['testvar'] = 'aaa bbb'
    execute("echo ${testvar//a/&} > #{output_file}")
    assert_equal "&&& bbb\n", File.read(output_file)
  end

  # Test no ampersand in replacement (behavior unchanged)
  def test_no_ampersand_simple_replacement
    ENV['testvar'] = 'hello world'
    execute("echo ${testvar/hello/hi} > #{output_file}")
    assert_equal "hi world\n", File.read(output_file)
  end

  def test_no_ampersand_global_replacement
    ENV['testvar'] = 'aaa bbb aaa'
    execute("echo ${testvar//aaa/xxx} > #{output_file}")
    assert_equal "xxx bbb xxx\n", File.read(output_file)
  end

  # Test toggle behavior
  def test_toggle_patsub_replacement
    ENV['testvar'] = 'test'

    # Default: enabled
    execute("echo ${testvar/test/[&]} > #{output_file}")
    assert_equal "[test]\n", File.read(output_file)

    # Disable
    execute('shopt -u patsub_replacement')
    execute("echo ${testvar/test/[&]} > #{output_file}")
    assert_equal "[&]\n", File.read(output_file)

    # Re-enable
    execute('shopt -s patsub_replacement')
    execute("echo ${testvar/test/[&]} > #{output_file}")
    assert_equal "[test]\n", File.read(output_file)
  end

  # Test edge cases
  def test_empty_replacement_with_ampersand
    ENV['testvar'] = 'hello'
    # Just & means replace with the match itself (no change)
    execute("echo ${testvar/hello/&} > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_ampersand_at_start_of_replacement
    ENV['testvar'] = 'abc'
    execute("echo ${testvar/abc/&xyz} > #{output_file}")
    assert_equal "abcxyz\n", File.read(output_file)
  end

  def test_ampersand_at_end_of_replacement
    ENV['testvar'] = 'abc'
    execute("echo ${testvar/abc/xyz&} > #{output_file}")
    assert_equal "xyzabc\n", File.read(output_file)
  end

  def test_only_escaped_ampersand
    ENV['testvar'] = 'test'
    execute("echo ${testvar/test/\\&\\&} > #{output_file}")
    assert_equal "&&\n", File.read(output_file)
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt patsub_replacement')
    end
    assert_match(/patsub_replacement/, output)
    assert_match(/on/, output)

    execute('shopt -u patsub_replacement')

    output = capture_output do
      execute('shopt patsub_replacement')
    end
    assert_match(/patsub_replacement/, output)
    assert_match(/off/, output)
  end
end
