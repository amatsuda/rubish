# frozen_string_literal: true

require_relative 'test_helper'

class TestVarnameRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_varname_redirect_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    @original_env = {}
    %w[fd FD myfd testfd].each do |var|
      @original_env[var] = ENV[var]
    end
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
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

  # Test lexer recognizes {varname} redirection pattern
  def test_lexer_recognizes_varname_redirect
    lexer = Rubish::Lexer.new('exec {fd}>file.txt')
    tokens = lexer.tokenize

    # Should have: WORD(exec), VARNAME_REDIRECT({fd}>), WORD(file.txt)
    assert_equal 3, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal 'exec', tokens[0].value
    assert_equal :VARNAME_REDIRECT, tokens[1].type
    assert_equal 'fd', tokens[1].value[:varname]
    assert_equal '>', tokens[1].value[:operator]
    assert_equal :WORD, tokens[2].type
    assert_equal 'file.txt', tokens[2].value
  end

  def test_lexer_recognizes_append_redirect
    lexer = Rubish::Lexer.new('exec {fd}>>file.txt')
    tokens = lexer.tokenize

    assert_equal :VARNAME_REDIRECT, tokens[1].type
    assert_equal 'fd', tokens[1].value[:varname]
    assert_equal '>>', tokens[1].value[:operator]
  end

  def test_lexer_recognizes_input_redirect
    lexer = Rubish::Lexer.new('exec {fd}<file.txt')
    tokens = lexer.tokenize

    assert_equal :VARNAME_REDIRECT, tokens[1].type
    assert_equal 'fd', tokens[1].value[:varname]
    assert_equal '<', tokens[1].value[:operator]
  end

  def test_lexer_recognizes_dup_output_redirect
    lexer = Rubish::Lexer.new('exec {fd}>&1')
    tokens = lexer.tokenize

    assert_equal :VARNAME_REDIRECT, tokens[1].type
    assert_equal 'fd', tokens[1].value[:varname]
    assert_equal '>&', tokens[1].value[:operator]
  end

  def test_lexer_recognizes_dup_input_redirect
    lexer = Rubish::Lexer.new('exec {fd}<&0')
    tokens = lexer.tokenize

    assert_equal :VARNAME_REDIRECT, tokens[1].type
    assert_equal 'fd', tokens[1].value[:varname]
    assert_equal '<&', tokens[1].value[:operator]
  end

  # Test that brace expansion is not confused with varname redirect
  def test_lexer_brace_expansion_not_varname_redirect
    lexer = Rubish::Lexer.new('echo {a,b,c}')
    tokens = lexer.tokenize

    # Should be: WORD(echo), WORD({a,b,c})
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal 'echo', tokens[0].value
    assert_equal '{a,b,c}', tokens[1].value
  end

  # Test parser creates VarnameRedirect AST node
  def test_parser_creates_varname_redirect_node
    lexer = Rubish::Lexer.new('exec {fd}>output.txt')
    tokens = lexer.tokenize
    parser = Rubish::Parser.new(tokens)
    ast = parser.parse

    assert_instance_of Rubish::AST::VarnameRedirect, ast
    assert_equal 'fd', ast.varname
    assert_equal '>', ast.operator
    assert_equal 'output.txt', ast.target
  end

  # Test FD allocation
  def test_fd_allocation_assigns_variable
    execute('exec {myfd}>' + output_file)

    # The variable should be set to an FD number >= 10
    assert_not_nil get_shell_var('myfd')
    fd_num = get_shell_var('myfd').to_i
    assert fd_num >= 10, "FD number should be >= 10, got #{fd_num}"
  end

  def test_multiple_fd_allocations_are_unique
    file1 = File.join(@tempdir, 'file1.txt')
    file2 = File.join(@tempdir, 'file2.txt')

    execute("exec {fd1}>#{file1}")
    fd1 = get_shell_var('fd1').to_i

    execute("exec {fd2}>#{file2}")
    fd2 = get_shell_var('fd2').to_i

    assert fd1 != fd2, 'FD numbers should be unique'
    assert fd1 >= 10
    assert fd2 >= 10
  end

  # varredir_close tests
  def test_varredir_close_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('varredir_close')
  end

  def test_varredir_close_can_be_enabled
    execute('shopt -s varredir_close')
    assert Rubish::Builtins.shopt_enabled?('varredir_close')
  end

  def test_varredir_close_can_be_disabled
    execute('shopt -s varredir_close')
    execute('shopt -u varredir_close')
    assert_false Rubish::Builtins.shopt_enabled?('varredir_close')
  end

  # Test the option is in SHELL_OPTIONS
  def test_varredir_close_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('varredir_close')
    # SHELL_OPTIONS stores [default_value, description] arrays
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['varredir_close'][0] # default off
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt varredir_close')
    end
    assert_match(/varredir_close/, output)
    assert_match(/off/, output)

    execute('shopt -s varredir_close')

    output = capture_output do
      execute('shopt varredir_close')
    end
    assert_match(/varredir_close/, output)
    assert_match(/on/, output)
  end

  # Test shopt -q for varredir_close
  def test_shopt_q_varredir_close
    # Default is disabled, so -q should return false
    result = Rubish::Builtins.run('shopt', ['-q', 'varredir_close'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'varredir_close'])
    result = Rubish::Builtins.run('shopt', ['-q', 'varredir_close'])
    assert result
  end

  # Test toggle behavior
  def test_toggle_varredir_close
    # Default: disabled
    assert_false Rubish::Builtins.shopt_enabled?('varredir_close')

    # Enable
    execute('shopt -s varredir_close')
    assert Rubish::Builtins.shopt_enabled?('varredir_close')

    # Disable
    execute('shopt -u varredir_close')
    assert_false Rubish::Builtins.shopt_enabled?('varredir_close')

    # Re-enable
    execute('shopt -s varredir_close')
    assert Rubish::Builtins.shopt_enabled?('varredir_close')
  end

  # Test that the option is listed in shopt output
  def test_option_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/varredir_close/, output)
  end
end
