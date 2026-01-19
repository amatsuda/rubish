# frozen_string_literal: true

require_relative 'test_helper'

class TestLexer < Test::Unit::TestCase
  def tokenize(input)
    Rubish::Lexer.new(input).tokenize
  end

  def test_simple_command
    tokens = tokenize('ls')
    assert_equal 1, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls', tokens[0].value
  end

  def test_command_with_args
    tokens = tokenize('ls -la /tmp')
    assert_equal 3, tokens.length
    assert_equal ['ls', '-la', '/tmp'], tokens.map(&:value)
  end

  def test_pipe
    tokens = tokenize('ls | grep foo')
    assert_equal 4, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :PIPE, tokens[1].type
    assert_equal '|', tokens[1].value
    assert_equal :WORD, tokens[2].type
  end

  def test_redirect_out
    tokens = tokenize('echo hello > /tmp/file')
    assert_equal 4, tokens.length
    assert_equal :REDIRECT_OUT, tokens[2].type
    assert_equal '>', tokens[2].value
  end

  def test_redirect_append
    tokens = tokenize('echo hello >> /tmp/file')
    assert_equal 4, tokens.length
    assert_equal :REDIRECT_APPEND, tokens[2].type
    assert_equal '>>', tokens[2].value
  end

  def test_redirect_in
    tokens = tokenize('cat < /tmp/file')
    assert_equal 3, tokens.length
    assert_equal :REDIRECT_IN, tokens[1].type
  end

  def test_semicolon
    tokens = tokenize('echo a; echo b')
    assert_equal 5, tokens.length
    assert_equal :SEMICOLON, tokens[2].type
  end

  def test_ampersand
    tokens = tokenize('sleep 10 &')
    assert_equal 3, tokens.length
    assert_equal :AMPERSAND, tokens[2].type
  end

  def test_double_quoted_string
    tokens = tokenize('echo "hello world"')
    assert_equal 2, tokens.length
    assert_equal '"hello world"', tokens[1].value
  end

  def test_single_quoted_string
    tokens = tokenize("echo 'hello world'")
    assert_equal 2, tokens.length
    assert_equal "'hello world'", tokens[1].value
  end

  # New tests for parser edge cases

  # Test |& (pipe both stdout and stderr)
  def test_pipe_both
    tokens = tokenize('cmd1 |& cmd2')
    assert_equal 3, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :PIPE_BOTH, tokens[1].type
    assert_equal '|&', tokens[1].value
    assert_equal :WORD, tokens[2].type
  end

  # Test ;& (case fall-through)
  def test_case_fall
    tokens = tokenize(';&')
    assert_equal 1, tokens.length
    assert_equal :CASE_FALL, tokens[0].type
    assert_equal ';&', tokens[0].value
  end

  # Test ;;& (case continue)
  def test_case_cont
    tokens = tokenize(';;&')
    assert_equal 1, tokens.length
    assert_equal :CASE_CONT, tokens[0].type
    assert_equal ';;&', tokens[0].value
  end

  # Test ;; (double semi)
  def test_double_semi
    tokens = tokenize(';;')
    assert_equal 1, tokens.length
    assert_equal :DOUBLE_SEMI, tokens[0].type
    assert_equal ';;', tokens[0].value
  end

  # Test case with fall-through
  def test_case_with_fall_through_tokens
    tokens = tokenize('case x in a) echo a ;& b) echo b ;; esac')
    types = tokens.map(&:type)
    assert_includes types, :CASE_FALL
    assert_includes types, :DOUBLE_SEMI
  end

  # Test case with continue
  def test_case_with_continue_tokens
    tokens = tokenize('case x in a) echo a ;;& b) echo b ;; esac')
    types = tokens.map(&:type)
    assert_includes types, :CASE_CONT
    assert_includes types, :DOUBLE_SEMI
  end

  # Ensure ;;& and ;& don't conflict with each other
  def test_case_terminators_no_conflict
    tokens = tokenize(';& ;;& ;;')
    assert_equal 3, tokens.length
    assert_equal :CASE_FALL, tokens[0].type
    assert_equal :CASE_CONT, tokens[1].type
    assert_equal :DOUBLE_SEMI, tokens[2].type
  end

  # Test path vs regexp distinction

  # Path with trailing slash should be WORD, not REGEXP
  def test_path_with_trailing_slash
    tokens = tokenize('ls /bin/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal '/bin/', tokens[1].value
  end

  # Absolute path without trailing slash should be WORD
  def test_absolute_path
    tokens = tokenize('ls /bin')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/bin', tokens[1].value
  end

  # Relative path with ./ prefix and trailing slash should be WORD
  def test_relative_path_with_trailing_slash
    tokens = tokenize('ls ./bin/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal './bin/', tokens[1].value
  end

  # Regexp with metacharacters should be REGEXP
  def test_regexp_with_metacharacters
    tokens = tokenize('grep /foo.*bar/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
    assert_equal '/foo.*bar/', tokens[1].value
  end

  # Regexp with anchors should be REGEXP
  def test_regexp_with_anchors
    tokens = tokenize('grep /^start/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
    assert_equal '/^start/', tokens[1].value
  end

  # Path-like content should be WORD even if it looks like a regexp
  def test_simple_path_not_regexp
    tokens = tokenize('cat /etc/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/etc/', tokens[1].value
  end

  # Multi-level path should be WORD
  def test_multi_level_path
    tokens = tokenize('ls /usr/local/bin')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/usr/local/bin', tokens[1].value
  end

  # Multi-level path with trailing slash should be WORD (regression test)
  def test_multi_level_path_with_trailing_slash
    tokens = tokenize('cd /opt/homebrew/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal '/opt/homebrew/', tokens[1].value
  end

  # Deep path with trailing slash should be WORD
  def test_deep_path_with_trailing_slash
    tokens = tokenize('ls /usr/local/Cellar/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/usr/local/Cellar/', tokens[1].value
  end

  # Path with hyphen should be WORD
  def test_path_with_hyphen
    tokens = tokenize('cat /var/log/my-app/errors.log')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/var/log/my-app/errors.log', tokens[1].value
  end

  # Path with underscore should be WORD
  def test_path_with_underscore
    tokens = tokenize('ls /home/user/my_project/')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
    assert_equal '/home/user/my_project/', tokens[1].value
  end

  # Path with dots should be WORD
  def test_path_with_dots
    tokens = tokenize('cat /etc/nginx/sites-enabled/example.com.conf')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[1].type
  end

  # Regexp with capture groups should be REGEXP
  def test_regexp_with_capture_groups
    tokens = tokenize('grep /(foo|bar)/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
  end

  # Regexp with character class should be REGEXP
  def test_regexp_with_character_class
    tokens = tokenize('grep /[a-z]+/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
  end

  # Regexp with quantifiers should be REGEXP
  def test_regexp_with_quantifiers
    tokens = tokenize('grep /fo+ba?r/')
    assert_equal 2, tokens.length
    assert_equal :REGEXP, tokens[1].type
  end

  # ==========================================================================
  # Function call syntax: cmd(arg1, arg2)
  # ==========================================================================

  # Single argument function call
  def test_func_call_single_arg
    tokens = tokenize('ls(-l)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal 'ls', tokens[0].value[:name]
    assert_equal ['-l'], tokens[0].value[:args]
  end

  # Multiple arguments function call
  def test_func_call_multiple_args
    tokens = tokenize('ls(-l, /tmp)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal 'ls', tokens[0].value[:name]
    assert_equal ['-l', '/tmp'], tokens[0].value[:args]
  end

  # Function call with path argument
  def test_func_call_path_arg
    tokens = tokenize('cd(/opt/homebrew)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal 'cd', tokens[0].value[:name]
    assert_equal ['/opt/homebrew'], tokens[0].value[:args]
  end

  # Function call with path with trailing slash
  def test_func_call_path_with_trailing_slash
    tokens = tokenize('cd(/opt/homebrew/)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['/opt/homebrew/'], tokens[0].value[:args]
  end

  # Function call with regex argument
  def test_func_call_regex_arg
    tokens = tokenize('grep(/pattern/)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal 'grep', tokens[0].value[:name]
    assert_equal ['/pattern/'], tokens[0].value[:args]
  end

  # Function call with regex with metacharacters
  def test_func_call_regex_metachar
    tokens = tokenize('grep(/error.*fatal/)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['/error.*fatal/'], tokens[0].value[:args]
  end

  # Function call with regex and file arg
  def test_func_call_regex_and_file
    tokens = tokenize('grep(/error/, log.txt)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['/error/', 'log.txt'], tokens[0].value[:args]
  end

  # Function call with quoted string
  def test_func_call_quoted_string
    tokens = tokenize('echo("hello world")')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['"hello world"'], tokens[0].value[:args]
  end

  # Function call with single-quoted string
  def test_func_call_single_quoted
    tokens = tokenize("echo('hello')")
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ["'hello'"], tokens[0].value[:args]
  end

  # Function call vs subshell - space before paren means subshell
  def test_func_call_vs_subshell
    tokens = tokenize('ls (foo)')
    assert_equal 4, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls', tokens[0].value
    assert_equal :LPAREN, tokens[1].type
    assert_equal :WORD, tokens[2].type
    assert_equal :RPAREN, tokens[3].type
  end

  # Empty parens should be function definition, not function call
  def test_empty_parens_is_func_def
    tokens = tokenize('foo()')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :PARENS, tokens[1].type
  end

  # Function call with whitespace around args
  def test_func_call_whitespace_args
    tokens = tokenize('ls( -l , /tmp )')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['-l', '/tmp'], tokens[0].value[:args]
  end

  # Function call with command substitution
  def test_func_call_command_substitution
    tokens = tokenize('echo($(date))')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['$(date)'], tokens[0].value[:args]
  end

  # Function call with variable
  def test_func_call_variable
    tokens = tokenize('echo($HOME)')
    assert_equal 1, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['$HOME'], tokens[0].value[:args]
  end

  # Function call followed by pipe
  def test_func_call_with_pipe
    tokens = tokenize('ls(-l) | grep foo')
    assert_equal 4, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal :PIPE, tokens[1].type
  end

  # Function call followed by redirection
  def test_func_call_with_redirect
    tokens = tokenize('ls(-l) > out.txt')
    assert_equal 3, tokens.length
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal :REDIRECT_OUT, tokens[1].type
  end

  # Ruby-style method calls with keyword args should NOT be func calls
  def test_ruby_keyword_args_not_func_call
    tokens = tokenize('cyan(prompt_pwd(expand_level: 2))')
    # Should be separate tokens, not a single FUNC_CALL
    assert_equal :WORD, tokens[0].type
    assert_equal 'cyan', tokens[0].value
    assert_equal :LPAREN, tokens[1].type
  end

  # Ruby-style method calls with multiple keyword args
  def test_ruby_multiple_keyword_args_not_func_call
    tokens = tokenize('method(foo: 1, bar: 2)')
    assert_equal :WORD, tokens[0].type
    assert_equal :LPAREN, tokens[1].type
  end

  # But simple shell args without colons should still be func calls
  def test_func_call_without_colons
    tokens = tokenize('cmd(arg1, arg2)')
    assert_equal :FUNC_CALL, tokens[0].type
  end

  # ==========================================================================
  # Method chain syntax: cmd.method(args)
  # ==========================================================================

  # Simple method chain
  def test_method_chain_simple
    tokens = tokenize('ls.grep(/foo/)')
    assert_equal 3, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls', tokens[0].value
    assert_equal :DOT, tokens[1].type
    assert_equal :FUNC_CALL, tokens[2].type
    assert_equal 'grep', tokens[2].value[:name]
  end

  # Multiple method chain
  def test_method_chain_multiple
    tokens = tokenize('ls.grep(/foo/).head(-5)')
    assert_equal 5, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :DOT, tokens[1].type
    assert_equal :FUNC_CALL, tokens[2].type
    assert_equal :DOT, tokens[3].type
    assert_equal :FUNC_CALL, tokens[4].type
  end

  # Filename with extension should not be method chain
  def test_filename_not_method_chain
    tokens = tokenize('cat file.txt')
    assert_equal 2, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal :WORD, tokens[1].type
    assert_equal 'file.txt', tokens[1].value
  end

  # Relative path should not be method chain
  def test_relative_path_not_method_chain
    tokens = tokenize('./script')
    assert_equal 1, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal './script', tokens[0].value
  end

  # Hidden file should not be method chain
  def test_hidden_file_not_method_chain
    tokens = tokenize('.hidden')
    assert_equal 1, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal '.hidden', tokens[0].value
  end

  # Method without parens should be filename
  def test_method_without_parens_is_filename
    tokens = tokenize('ls.sort')
    assert_equal 1, tokens.length
    assert_equal :WORD, tokens[0].type
    assert_equal 'ls.sort', tokens[0].value
  end

  # Positive integers in func call stay as-is (wrapper handles head/tail)
  def test_func_call_positive_int_unchanged
    tokens = tokenize('head(5)')
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['5'], tokens[0].value[:args]
  end

  # Negative integers stay as-is
  def test_func_call_negative_int_stays
    tokens = tokenize('head(-5)')
    assert_equal :FUNC_CALL, tokens[0].type
    assert_equal ['-5'], tokens[0].value[:args]
  end
end
