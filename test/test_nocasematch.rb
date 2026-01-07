# frozen_string_literal: true

require_relative 'test_helper'

class TestNocasematch < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_nocasematch_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  def test_nocasematch_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('nocasematch')
  end

  def test_nocasematch_can_be_enabled
    execute('shopt -s nocasematch')
    assert Rubish::Builtins.shopt_enabled?('nocasematch')
  end

  def test_nocasematch_can_be_disabled
    execute('shopt -s nocasematch')
    execute('shopt -u nocasematch')
    assert_false Rubish::Builtins.shopt_enabled?('nocasematch')
  end

  # Case statement tests
  def test_case_statement_case_sensitive_by_default
    output_file = File.join(@tempdir, 'output.txt')
    execute("case foo in FOO) echo matched > #{output_file};; esac")
    assert_false File.exist?(output_file)
  end

  def test_case_statement_case_insensitive_with_nocasematch
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s nocasematch')
    execute("case foo in FOO) echo matched > #{output_file};; esac")
    assert File.exist?(output_file)
    assert_equal "matched\n", File.read(output_file)
  end

  def test_case_statement_pattern_with_nocasematch
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s nocasematch')
    execute("case HELLO in h*) echo matched > #{output_file};; esac")
    assert File.exist?(output_file)
  end

  def test_case_statement_respects_nocasematch_toggle
    output_file = File.join(@tempdir, 'output.txt')

    # Disabled - should not match
    execute("case foo in FOO) echo matched > #{output_file};; esac")
    assert_false File.exist?(output_file)

    # Enable - should match
    execute('shopt -s nocasematch')
    execute("case bar in BAR) echo matched > #{output_file};; esac")
    assert File.exist?(output_file)
    FileUtils.rm(output_file)

    # Disable - should not match again
    execute('shopt -u nocasematch')
    execute("case baz in BAZ) echo matched > #{output_file};; esac")
    assert_false File.exist?(output_file)
  end

  # [[ == ]] pattern matching tests
  def test_conditional_pattern_case_sensitive_by_default
    output_file = File.join(@tempdir, 'output.txt')
    execute("[[ foo == FOO ]] && echo matched > #{output_file}")
    assert_false File.exist?(output_file)
  end

  def test_conditional_pattern_case_insensitive_with_nocasematch
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s nocasematch')
    execute("[[ foo == FOO ]] && echo matched > #{output_file}")
    assert File.exist?(output_file)
  end

  def test_conditional_glob_pattern_with_nocasematch
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s nocasematch')
    execute("[[ HELLO == h* ]] && echo matched > #{output_file}")
    assert File.exist?(output_file)
  end

  def test_conditional_not_equal_with_nocasematch
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s nocasematch')
    # With nocasematch, foo == FOO, so foo != FOO should be false
    execute("[[ foo != FOO ]] && echo matched > #{output_file}")
    assert_false File.exist?(output_file)
  end

  # [[ =~ ]] regex matching tests
  def test_regex_case_sensitive_by_default
    output_file = File.join(@tempdir, 'output.txt')
    execute("[[ hello =~ HELLO ]] && echo matched > #{output_file}")
    assert_false File.exist?(output_file)
  end

  def test_regex_case_insensitive_with_nocasematch
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s nocasematch')
    execute("[[ hello =~ HELLO ]] && echo matched > #{output_file}")
    assert File.exist?(output_file)
  end

  def test_regex_pattern_with_nocasematch
    output_file = File.join(@tempdir, 'output.txt')
    execute('shopt -s nocasematch')
    execute("[[ HELLO =~ ^h.*o$ ]] && echo matched > #{output_file}")
    assert File.exist?(output_file)
  end

  def test_regex_capture_groups_with_nocasematch
    execute('shopt -s nocasematch')
    execute('[[ HELLO =~ ^(H)(E)(L)(L)(O)$ ]]')
    # RUBISH_REMATCH should contain the matches (case-insensitive)
    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_not_nil rematch
    assert_equal 'HELLO', rematch[0]
  end

  # __case_match helper tests
  def test_case_match_without_nocasematch
    assert @repl.send(:__case_match, 'foo', 'foo')
    assert_false @repl.send(:__case_match, 'foo', 'FOO')
    assert_false @repl.send(:__case_match, 'FOO', 'foo')
  end

  def test_case_match_with_nocasematch
    execute('shopt -s nocasematch')
    assert @repl.send(:__case_match, 'foo', 'foo')
    assert @repl.send(:__case_match, 'foo', 'FOO')
    assert @repl.send(:__case_match, 'FOO', 'foo')
    assert @repl.send(:__case_match, 'FoO', 'fOo')
  end

  def test_case_match_wildcard_with_nocasematch
    execute('shopt -s nocasematch')
    assert @repl.send(:__case_match, 'f*', 'FOO')
    assert @repl.send(:__case_match, 'F*', 'foo')
    assert @repl.send(:__case_match, '*.TXT', 'file.txt')
    assert @repl.send(:__case_match, '*.txt', 'FILE.TXT')
  end
end
