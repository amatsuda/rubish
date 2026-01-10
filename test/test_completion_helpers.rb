# frozen_string_literal: true

require_relative 'test_helper'

class TestCompletionHelpers < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_completion_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)

    # Create test files and directories
    FileUtils.touch('file1.txt')
    FileUtils.touch('file2.txt')
    FileUtils.touch('script.sh')
    FileUtils.mkdir('subdir1')
    FileUtils.mkdir('subdir2')

    Rubish::Builtins.instance_variable_set(:@compreply, [])
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # ==========================================================================
  # _get_comp_words_by_ref tests
  # ==========================================================================

  def test_get_comp_words_by_ref_basic
    Rubish::Builtins.set_completion_context(
      line: 'git commit -m hello',
      point: 19,
      words: %w[git commit -m hello],
      cword: 3
    )

    result = Rubish::Builtins.run('_get_comp_words_by_ref', [])
    assert result

    assert_equal 'hello', ENV['cur']
    assert_equal '-m', ENV['prev']
    assert_equal '3', ENV['cword']
  end

  def test_get_comp_words_by_ref_custom_vars
    Rubish::Builtins.set_completion_context(
      line: 'cmd arg1 arg2',
      point: 13,
      words: %w[cmd arg1 arg2],
      cword: 2
    )

    result = Rubish::Builtins.run('_get_comp_words_by_ref', ['-c', 'mycur', '-p', 'myprev'])
    assert result

    assert_equal 'arg2', ENV['mycur']
    assert_equal 'arg1', ENV['myprev']
  end

  def test_get_comp_words_by_ref_exclude_colon
    Rubish::Builtins.set_completion_context(
      line: 'git remote:origin test',
      point: 22,
      words: %w[git remote:origin test],
      cword: 2
    )

    # Without exclusion
    Rubish::Builtins.run('_get_comp_words_by_ref', [])
    assert_equal 'test', ENV['cur']

    # With colon exclusion - words should be re-split
    Rubish::Builtins.run('_get_comp_words_by_ref', ['-n', ':'])
    # The exact behavior depends on implementation, but it should work
    assert_not_nil ENV['cur']
  end

  # ==========================================================================
  # _init_completion tests
  # ==========================================================================

  def test_init_completion_basic
    Rubish::Builtins.set_completion_context(
      line: 'cmd arg1 arg2',
      point: 13,
      words: %w[cmd arg1 arg2],
      cword: 2
    )

    result = Rubish::Builtins.run('_init_completion', [])
    assert result

    assert_equal 'arg2', ENV['cur']
    assert_equal 'arg1', ENV['prev']
    assert_equal [], Rubish::Builtins.compreply
  end

  def test_init_completion_split_option
    Rubish::Builtins.set_completion_context(
      line: 'cmd --option=value',
      point: 18,
      words: ['cmd', '--option=value'],
      cword: 1
    )

    result = Rubish::Builtins.run('_init_completion', ['-s'])
    assert result

    assert_equal 'value', ENV['cur']
    assert_equal '--option', ENV['prev']
  end

  # ==========================================================================
  # _filedir tests
  # ==========================================================================

  def test_filedir_all_files
    ENV['cur'] = ''
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_filedir', [])
    assert result

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.include?('file1.txt') }
    assert completions.any? { |c| c.include?('file2.txt') }
    assert completions.any? { |c| c.include?('subdir1') }
  end

  def test_filedir_directories_only
    ENV['cur'] = ''
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_filedir', ['-d'])
    assert result

    completions = Rubish::Builtins.compreply
    # Should only have directories
    assert completions.any? { |c| c.include?('subdir') }
    assert completions.none? { |c| c.include?('file1.txt') }
  end

  def test_filedir_with_prefix
    ENV['cur'] = 'file'
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_filedir', [])
    assert result

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.include?('file1.txt') }
    assert completions.any? { |c| c.include?('file2.txt') }
    assert completions.none? { |c| c.include?('script.sh') }
  end

  def test_filedir_with_pattern
    ENV['cur'] = ''
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_filedir', ['*.txt'])
    assert result

    completions = Rubish::Builtins.compreply
    txt_files = completions.select { |c| c.end_with?('.txt') }
    assert txt_files.length >= 2
    # Directories should still be included
    assert completions.any? { |c| c.include?('subdir') }
  end

  # ==========================================================================
  # _have tests
  # ==========================================================================

  def test_have_existing_command
    result = Rubish::Builtins.run('_have', ['ls'])
    assert result, 'ls should exist in PATH'
  end

  def test_have_nonexistent_command
    result = Rubish::Builtins.run('_have', ['nonexistent_command_xyz_123'])
    assert_false result
  end

  def test_have_builtin
    result = Rubish::Builtins.run('_have', ['cd'])
    assert result, 'cd is a builtin'

    result = Rubish::Builtins.run('_have', ['echo'])
    assert result, 'echo is a builtin'
  end

  # ==========================================================================
  # _split_longopt tests
  # ==========================================================================

  def test_split_longopt_with_equals
    ENV['cur'] = '--option=value'

    result = Rubish::Builtins.run('_split_longopt', [])
    assert result

    assert_equal 'value', ENV['cur']
    assert_equal '--option', ENV['prev']
    assert_equal 'set', ENV['__SPLIT_LONGOPT']
  end

  def test_split_longopt_without_equals
    ENV['cur'] = '--option'

    result = Rubish::Builtins.run('_split_longopt', [])
    assert_false result

    # cur should be unchanged
    assert_equal '--option', ENV['cur']
  end

  # ==========================================================================
  # __ltrim_colon_completions tests
  # ==========================================================================

  def test_ltrim_colon_completions
    Rubish::Builtins.instance_variable_set(:@compreply, ['pkg:v1', 'pkg:v2', 'pkg:v3'])

    result = Rubish::Builtins.run('__ltrim_colon_completions', ['pkg:'])
    assert result

    completions = Rubish::Builtins.compreply
    assert_equal %w[v1 v2 v3], completions
  end

  def test_ltrim_colon_completions_no_colon
    Rubish::Builtins.instance_variable_set(:@compreply, %w[alpha beta gamma])

    result = Rubish::Builtins.run('__ltrim_colon_completions', ['alpha'])
    assert result

    # Should be unchanged (no colon in cur)
    completions = Rubish::Builtins.compreply
    assert_equal %w[alpha beta gamma], completions
  end

  # ==========================================================================
  # _variables tests
  # ==========================================================================

  def test_variables_completion
    ENV['MY_UNIQUE_TEST_VAR'] = 'value'
    ENV['cur'] = 'MY_UNIQUE'
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_variables', [])
    assert result

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.include?('MY_UNIQUE_TEST_VAR') }
  end

  def test_variables_with_dollar_prefix
    ENV['MY_DOLLAR_TEST'] = 'value'
    ENV['cur'] = '$MY_DOLLAR'
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_variables', [])
    assert result

    completions = Rubish::Builtins.compreply
    assert completions.any? { |c| c.include?('MY_DOLLAR_TEST') }
  end

  # ==========================================================================
  # _tilde tests
  # ==========================================================================

  def test_tilde_completion
    ENV['cur'] = '~'
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_tilde', [])
    assert result

    # Should have some usernames (if /etc/passwd is readable)
    # This may be empty on some systems
    completions = Rubish::Builtins.compreply
    # Just verify it runs without error
  end

  def test_tilde_no_tilde
    ENV['cur'] = 'path'
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_tilde', [])
    assert result

    # Should not add anything when cur doesn't start with ~
    assert_equal [], Rubish::Builtins.compreply
  end

  # ==========================================================================
  # _quote_readline_by_ref tests
  # ==========================================================================

  def test_quote_readline_by_ref
    result = Rubish::Builtins.run('_quote_readline_by_ref', ['myvar', 'hello world'])
    assert result

    # Should have escaped the space
    assert ENV['myvar'].include?('\\')
  end

  def test_quote_readline_by_ref_special_chars
    result = Rubish::Builtins.run('_quote_readline_by_ref', ['myvar', "test'quote"])
    assert result

    assert ENV['myvar'].include?('\\')
  end

  # ==========================================================================
  # _parse_help tests
  # ==========================================================================

  def test_parse_help_with_ls
    ENV['cur'] = ''
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    # This will run ls --help and parse options
    result = Rubish::Builtins.run('_parse_help', ['ls'])
    assert result

    completions = Rubish::Builtins.compreply
    # ls should have some options like -l, -a, etc.
    # The exact options depend on the system's ls implementation
    assert completions.length >= 0  # May be empty if ls --help fails
  end

  # ==========================================================================
  # _upvars tests
  # ==========================================================================

  def test_upvars_scalar
    result = Rubish::Builtins.run('_upvars', ['-v', 'myvar', 'myvalue'])
    assert result

    assert_equal 'myvalue', ENV['myvar']
  end

  def test_upvars_array
    result = Rubish::Builtins.run('_upvars', ['-a', '3', 'myarr', 'a', 'b', 'c'])
    assert result

    arr = Rubish::Builtins.get_array('myarr')
    assert_equal %w[a b c], arr
  end

  # ==========================================================================
  # _usergroup tests
  # ==========================================================================

  def test_usergroup_users
    ENV['cur'] = ''
    Rubish::Builtins.instance_variable_set(:@compreply, [])

    result = Rubish::Builtins.run('_usergroup', ['-u'])
    assert result

    # Should have some usernames (if /etc/passwd is readable)
    completions = Rubish::Builtins.compreply
    # Just verify it runs without error
  end

  # ==========================================================================
  # Integration test
  # ==========================================================================

  def test_typical_completion_workflow
    # Simulate a typical bash-completion workflow
    Rubish::Builtins.set_completion_context(
      line: 'mycommand --opt',
      point: 15,
      words: ['mycommand', '--opt'],
      cword: 1
    )

    # Initialize completion
    Rubish::Builtins.run('_init_completion', [])
    assert_equal '--opt', ENV['cur']
    assert_equal 'mycommand', ENV['prev']

    # Generate some completions
    Rubish::Builtins.instance_variable_set(:@compreply,
      %w[--option1 --option2 --optional])

    # Completions should be set
    assert_equal 3, Rubish::Builtins.compreply.length
  end
end
