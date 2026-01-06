# frozen_string_literal: true

require_relative 'test_helper'

class TestCdspell < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_cdspell_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  def test_cdspell_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('cdspell')
  end

  def test_cdspell_no_correction_when_disabled
    FileUtils.mkdir_p('testdir')

    capture_stderr { execute('cd tsetdir') }
    # Should still be in tempdir since cdspell is disabled
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_cdspell_corrects_transposition
    FileUtils.mkdir_p('testdir')

    execute('shopt -s cdspell')
    stderr = capture_stderr { execute('cd tsetdir') }  # transposed 'es' -> 'se'
    assert_match(/testdir/, stderr)
    assert_equal File.realpath(File.join(@tempdir, 'testdir')), File.realpath(Dir.pwd)
  end

  def test_cdspell_corrects_missing_char
    FileUtils.mkdir_p('documents')

    execute('shopt -s cdspell')
    stderr = capture_stderr { execute('cd docments') }  # missing 'u'
    assert_match(/documents/, stderr)
    assert_equal File.realpath(File.join(@tempdir, 'documents')), File.realpath(Dir.pwd)
  end

  def test_cdspell_corrects_extra_char
    FileUtils.mkdir_p('src')

    execute('shopt -s cdspell')
    stderr = capture_stderr { execute('cd srrc') }  # extra 'r'
    assert_match(/src/, stderr)
    assert_equal File.realpath(File.join(@tempdir, 'src')), File.realpath(Dir.pwd)
  end

  def test_cdspell_corrects_wrong_char
    FileUtils.mkdir_p('config')

    execute('shopt -s cdspell')
    stderr = capture_stderr { execute('cd canfig') }  # 'o' -> 'a'
    assert_match(/config/, stderr)
    assert_equal File.realpath(File.join(@tempdir, 'config')), File.realpath(Dir.pwd)
  end

  def test_cdspell_corrects_case
    FileUtils.mkdir_p('MyFolder')

    execute('shopt -s cdspell')
    capture_stderr { execute('cd myfolder') }
    # On case-insensitive filesystems (macOS), this works without correction
    # On case-sensitive filesystems (Linux), cdspell corrects it
    # Either way, we should end up in the directory
    assert_equal File.realpath(File.join(@tempdir, 'MyFolder')), File.realpath(Dir.pwd)
  end

  def test_cdspell_no_correction_for_completely_wrong_name
    FileUtils.mkdir_p('testdir')

    execute('shopt -s cdspell')
    capture_stderr { execute('cd xyz') }
    # Should still be in tempdir since correction not possible
    assert_equal File.realpath(@tempdir), File.realpath(Dir.pwd)
  end

  def test_cdspell_corrects_nested_path
    FileUtils.mkdir_p('parent/child')

    execute('shopt -s cdspell')
    stderr = capture_stderr { execute('cd praent/chlid') }  # typos in both components
    assert_match(/parent\/child/, stderr)
    assert_equal File.realpath(File.join(@tempdir, 'parent/child')), File.realpath(Dir.pwd)
  end

  def test_cdspell_exact_match_no_output
    FileUtils.mkdir_p('exact')

    execute('shopt -s cdspell')
    stderr = capture_stderr { execute('cd exact') }
    # No correction output when exact match
    assert_equal '', stderr
    assert_equal File.realpath(File.join(@tempdir, 'exact')), File.realpath(Dir.pwd)
  end

  def test_cdspell_with_absolute_path
    subdir = File.join(@tempdir, 'absolute')
    FileUtils.mkdir_p(subdir)

    execute('shopt -s cdspell')
    typo_path = File.join(@tempdir, 'absolut')  # missing 'e'
    stderr = capture_stderr { execute("cd #{typo_path}") }
    assert_match(/absolute/, stderr)
    assert_equal File.realpath(subdir), File.realpath(Dir.pwd)
  end
end
