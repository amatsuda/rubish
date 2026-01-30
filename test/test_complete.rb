# frozen_string_literal: true

require_relative 'test_helper'

class TestComplete < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_complete_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    Rubish::Builtins.clear_completions
  end

  def teardown
    Rubish::Builtins.clear_completions
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end


  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test complete is a builtin
  def test_complete_is_builtin
    assert Rubish::Builtins.builtin?('complete')
  end

  # Test compgen is a builtin
  def test_compgen_is_builtin
    assert Rubish::Builtins.builtin?('compgen')
  end

  # Test complete with no args shows usage
  def test_complete_no_args
    output = capture_output do
      result = Rubish::Builtins.run('complete', [])
      assert_false result
    end
    assert_match(/usage/, output)
  end

  # Test complete -f sets file completion
  def test_complete_f_files
    result = Rubish::Builtins.run('complete', ['-f', 'mycommand'])
    assert result

    spec = Rubish::Builtins.get_completion_spec('mycommand')
    assert_not_nil spec
    assert_includes spec[:actions], :file
  end

  # Test complete -d sets directory completion
  def test_complete_d_directories
    result = Rubish::Builtins.run('complete', ['-d', 'mycommand'])
    assert result

    spec = Rubish::Builtins.get_completion_spec('mycommand')
    assert_includes spec[:actions], :directory
  end

  # Test complete -W sets wordlist
  def test_complete_W_wordlist
    result = Rubish::Builtins.run('complete', ['-W', 'foo bar baz', 'mycommand'])
    assert result

    spec = Rubish::Builtins.get_completion_spec('mycommand')
    assert_equal 'foo bar baz', spec[:wordlist]
  end

  # Test complete -F sets function
  def test_complete_F_function
    result = Rubish::Builtins.run('complete', ['-F', '_my_completion', 'mycommand'])
    assert result

    spec = Rubish::Builtins.get_completion_spec('mycommand')
    assert_equal '_my_completion', spec[:function]
  end

  # Test complete -p prints completions
  def test_complete_p_prints
    Rubish::Builtins.run('complete', ['-f', 'cmd1'])
    Rubish::Builtins.run('complete', ['-d', 'cmd2'])

    output = capture_output { Rubish::Builtins.run('complete', ['-p']) }
    assert_match(/complete -f cmd1/, output)
    assert_match(/complete -d cmd2/, output)
  end

  # Test complete -p works with default completions (specs without all keys)
  def test_complete_p_with_default_completions
    # Setup default completions (which have specs without :options key)
    Rubish::Builtins.setup_default_completions

    output = capture_output { Rubish::Builtins.run('complete', ['-p']) }
    assert_match(/complete -F _git git/, output)
    assert_match(/complete -F _ssh ssh/, output)
    assert_match(/complete -F _cd cd/, output)
  end

  # Test complete -p with specific command
  def test_complete_p_specific
    Rubish::Builtins.run('complete', ['-f', 'mycommand'])

    output = capture_output { Rubish::Builtins.run('complete', ['-p', 'mycommand']) }
    assert_match(/complete -f mycommand/, output)
  end

  # Test complete -r removes completions
  def test_complete_r_removes
    Rubish::Builtins.run('complete', ['-f', 'mycommand'])
    assert_not_nil Rubish::Builtins.get_completion_spec('mycommand')

    Rubish::Builtins.run('complete', ['-r', 'mycommand'])
    assert_nil Rubish::Builtins.get_completion_spec('mycommand')
  end

  # Test complete -r without args removes all
  def test_complete_r_removes_all
    Rubish::Builtins.run('complete', ['-f', 'cmd1'])
    Rubish::Builtins.run('complete', ['-d', 'cmd2'])

    Rubish::Builtins.run('complete', ['-r'])
    assert Rubish::Builtins.current_state.completions.empty?
  end

  # Test complete with invalid option
  def test_complete_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('complete', ['-z', 'mycommand'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test compgen -b lists builtins
  def test_compgen_b_builtins
    output = capture_output { Rubish::Builtins.run('compgen', ['-b']) }
    assert_match(/^cd$/, output)
    assert_match(/^echo$/, output)
    assert_match(/^exit$/, output)
  end

  # Test compgen -b with prefix
  def test_compgen_b_with_prefix
    output = capture_output { Rubish::Builtins.run('compgen', ['-b', 'ec']) }
    assert_match(/^echo$/, output)
    assert_no_match(/^cd$/, output)
  end

  # Test compgen -W wordlist
  def test_compgen_W_wordlist
    output = capture_output { Rubish::Builtins.run('compgen', ['-W', 'apple banana cherry', 'ba']) }
    assert_equal "banana\n", output
  end

  # Test compgen -f files
  def test_compgen_f_files
    FileUtils.touch('file1.txt')
    FileUtils.touch('file2.txt')
    FileUtils.mkdir('subdir')

    output = capture_output { Rubish::Builtins.run('compgen', ['-f', 'file']) }
    assert_match(/file1\.txt/, output)
    assert_match(/file2\.txt/, output)
  end

  # Test compgen -d directories
  def test_compgen_d_directories
    FileUtils.touch('file1.txt')
    FileUtils.mkdir('subdir1')
    FileUtils.mkdir('subdir2')

    output = capture_output { Rubish::Builtins.run('compgen', ['-d', 'sub']) }
    assert_match(/subdir1/, output)
    assert_match(/subdir2/, output)
    assert_no_match(/file1/, output)
  end

  # Test compgen -a aliases
  def test_compgen_a_aliases
    Rubish::Builtins.run('alias', ['ll=ls -la'])
    Rubish::Builtins.run('alias', ['la=ls -a'])

    output = capture_output { Rubish::Builtins.run('compgen', ['-a', 'l']) }
    assert_match(/ll/, output)
    assert_match(/la/, output)
  end

  # Test compgen -v variables
  def test_compgen_v_variables
    ENV['MY_TEST_VAR'] = 'value'

    output = capture_output { Rubish::Builtins.run('compgen', ['-v', 'MY_TEST']) }
    assert_match(/MY_TEST_VAR/, output)
  end

  # Test compgen with -P prefix
  def test_compgen_P_prefix
    output = capture_output { Rubish::Builtins.run('compgen', ['-W', 'foo bar', '-P', '--', 'f']) }
    assert_equal "--foo\n", output
  end

  # Test compgen with -S suffix
  def test_compgen_S_suffix
    output = capture_output { Rubish::Builtins.run('compgen', ['-W', 'foo bar', '-S', '=', 'f']) }
    assert_equal "foo=\n", output
  end

  # Test compgen with invalid option
  def test_compgen_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('compgen', ['-z'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test type identifies complete as builtin
  def test_type_identifies_complete_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['complete']) }
    assert_match(/complete is a shell builtin/, output)
  end

  # Test type identifies compgen as builtin
  def test_type_identifies_compgen_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['compgen']) }
    assert_match(/compgen is a shell builtin/, output)
  end

  # Test complete via REPL
  def test_complete_via_repl
    execute('complete -W "one two three" testcmd')
    spec = Rubish::Builtins.get_completion_spec('testcmd')
    assert_equal 'one two three', spec[:wordlist]
  end

  # Test compgen via REPL
  def test_compgen_via_repl
    output = capture_output { execute('compgen -W "apple banana" a') }
    assert_equal "apple\n", output
  end

  # Test complete multiple commands
  def test_complete_multiple_commands
    result = Rubish::Builtins.run('complete', ['-f', 'cmd1', 'cmd2', 'cmd3'])
    assert result

    assert_not_nil Rubish::Builtins.get_completion_spec('cmd1')
    assert_not_nil Rubish::Builtins.get_completion_spec('cmd2')
    assert_not_nil Rubish::Builtins.get_completion_spec('cmd3')
  end

  # Test complete combined flags
  def test_complete_combined_flags
    result = Rubish::Builtins.run('complete', ['-df', 'mycommand'])
    assert result

    spec = Rubish::Builtins.get_completion_spec('mycommand')
    assert_includes spec[:actions], :directory
    assert_includes spec[:actions], :file
  end

  # Function-based completion tests
  def test_function_completion_sets_compreply
    # Define a completion function
    execute('_testcomplete() { COMPREPLY=(alpha beta gamma); }')
    execute('complete -F _testcomplete testcmd')

    # Set up completion context
    Rubish::Builtins.set_completion_context(
      line: 'testcmd a',
      point: 9,
      words: %w[testcmd a],
      cword: 1
    )

    # Call the function
    @repl.send(:call_function, '_testcomplete', %w[testcmd a testcmd])

    # Verify COMPREPLY
    assert_equal %w[alpha beta gamma], Rubish::Builtins.compreply
  end

  def test_function_completion_receives_arguments
    # Define a function that stores its arguments
    execute('_argtest() { echo "$1 $2 $3" > ' + output_file + '; COMPREPLY=(); }')
    execute('complete -F _argtest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd --opt val',
      point: 17,
      words: %w[testcmd --opt val],
      cword: 2
    )

    @repl.send(:call_function, '_argtest', %w[testcmd val --opt])

    # Verify function received: $1=command, $2=current word, $3=previous word
    assert_equal "testcmd val --opt\n", File.read(output_file)
  end

  def test_function_completion_uses_comp_words
    # Define a function that uses COMP_WORDS
    execute('_wordstest() { echo "${COMP_WORDS[0]} ${COMP_WORDS[1]}" > ' + output_file + '; COMPREPLY=(); }')
    execute('complete -F _wordstest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd arg1',
      point: 12,
      words: %w[testcmd arg1],
      cword: 1
    )

    @repl.send(:call_function, '_wordstest', %w[testcmd arg1 testcmd])

    assert_equal "testcmd arg1\n", File.read(output_file)
  end

  def test_function_completion_uses_comp_cword
    execute('_cwordtest() { echo "$COMP_CWORD" > ' + output_file + '; COMPREPLY=(); }')
    execute('complete -F _cwordtest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd arg1 arg2',
      point: 17,
      words: %w[testcmd arg1 arg2],
      cword: 2
    )

    @repl.send(:call_function, '_cwordtest', %w[testcmd arg2 arg1])

    assert_equal "2\n", File.read(output_file)
  end

  def test_function_completion_context_dependent
    # Function that changes completion based on previous word
    execute('_contexttest() {
      if [ "$3" = "--file" ]; then
        COMPREPLY=(file1.txt file2.txt)
      else
        COMPREPLY=(--help --version --file)
      fi
    }')
    execute('complete -F _contexttest testcmd')

    # Test without --file
    Rubish::Builtins.set_completion_context(
      line: 'testcmd --',
      point: 10,
      words: %w[testcmd --],
      cword: 1
    )
    @repl.send(:call_function, '_contexttest', %w[testcmd -- testcmd])
    assert_equal %w[--help --version --file], Rubish::Builtins.compreply

    # Test with --file as previous word
    Rubish::Builtins.set_completion_context(
      line: 'testcmd --file f',
      point: 16,
      words: %w[testcmd --file f],
      cword: 2
    )
    @repl.send(:call_function, '_contexttest', %w[testcmd f --file])
    assert_equal %w[file1.txt file2.txt], Rubish::Builtins.compreply
  end

  def test_function_completion_clears_context
    Rubish::Builtins.set_completion_context(
      line: 'testcmd',
      point: 7,
      words: ['testcmd'],
      cword: 0
    )

    Rubish::Builtins.clear_completion_context
    assert_equal '', Rubish::Builtins.comp_line
    assert_equal 0, Rubish::Builtins.comp_cword
    assert_equal [], Rubish::Builtins.compreply
  end

  # ==========================================================================
  # Programmable completion - shell variable exposure tests
  # ==========================================================================

  def test_comp_line_exposed_as_env_var
    Rubish::Builtins.set_completion_context(
      line: 'mycmd --option value',
      point: 20,
      words: %w[mycmd --option value],
      cword: 2
    )

    assert_equal 'mycmd --option value', ENV['COMP_LINE']
    assert_equal '20', ENV['COMP_POINT']
    assert_equal '2', ENV['COMP_CWORD']
    assert_equal '9', ENV['COMP_TYPE']
    assert_equal '9', ENV['COMP_KEY']
  end

  def test_comp_words_exposed_as_array
    Rubish::Builtins.set_completion_context(
      line: 'mycmd arg1 arg2',
      point: 15,
      words: %w[mycmd arg1 arg2],
      cword: 2
    )

    words = Rubish::Builtins.get_array('COMP_WORDS')
    assert_equal %w[mycmd arg1 arg2], words
  end

  def test_compreply_array_synced_with_class_variable
    Rubish::Builtins.set_completion_context(
      line: 'mycmd ',
      point: 6,
      words: %w[mycmd],
      cword: 1
    )

    # Simulate shell function setting COMPREPLY=(opt1 opt2)
    Rubish::Builtins.set_array('COMPREPLY', %w[opt1 opt2])
    Rubish::Builtins.compreply = %w[opt1 opt2]

    # Both should have the same values
    assert_equal %w[opt1 opt2], Rubish::Builtins.get_array('COMPREPLY')
    assert_equal %w[opt1 opt2], Rubish::Builtins.compreply
  end

  def test_clear_context_removes_env_vars
    Rubish::Builtins.set_completion_context(
      line: 'testcmd',
      point: 7,
      words: ['testcmd'],
      cword: 0
    )

    assert_not_nil ENV['COMP_LINE']
    assert_not_nil ENV['COMP_CWORD']

    Rubish::Builtins.clear_completion_context

    assert_nil ENV['COMP_LINE']
    assert_nil ENV['COMP_CWORD']
    assert_nil ENV['COMP_POINT']
    assert_nil ENV['COMP_TYPE']
    assert_nil ENV['COMP_KEY']
    assert_equal [], Rubish::Builtins.get_array('COMP_WORDS')
    assert_equal [], Rubish::Builtins.get_array('COMPREPLY')
  end

  def test_function_uses_comp_line
    execute('_linetest() { echo "$COMP_LINE" > ' + output_file + '; COMPREPLY=(); }')
    execute('complete -F _linetest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd --option value',
      point: 22,
      words: %w[testcmd --option value],
      cword: 2
    )

    @repl.send(:call_function, '_linetest', %w[testcmd value --option])

    assert_equal "testcmd --option value\n", File.read(output_file)
  end

  def test_function_uses_comp_point
    execute('_pointtest() { echo "$COMP_POINT" > ' + output_file + '; COMPREPLY=(); }')
    execute('complete -F _pointtest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd arg',
      point: 11,
      words: %w[testcmd arg],
      cword: 1
    )

    @repl.send(:call_function, '_pointtest', %w[testcmd arg testcmd])

    assert_equal "11\n", File.read(output_file)
  end

  def test_function_modifies_compreply_array
    execute('_modifytest() { COMPREPLY=(result1 result2 result3); }')
    execute('complete -F _modifytest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd ',
      point: 8,
      words: %w[testcmd],
      cword: 1
    )

    @repl.send(:call_function, '_modifytest', %w[testcmd '' testcmd])

    # Both the class variable and array should have the results
    assert_equal %w[result1 result2 result3], Rubish::Builtins.compreply
    assert_equal %w[result1 result2 result3], Rubish::Builtins.get_array('COMPREPLY')
  end

  def test_function_appends_to_compreply
    execute('_appendtest() { COMPREPLY=(initial); COMPREPLY+=(added1 added2); }')
    execute('complete -F _appendtest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd ',
      point: 8,
      words: %w[testcmd],
      cword: 1
    )

    @repl.send(:call_function, '_appendtest', %w[testcmd '' testcmd])

    assert_equal %w[initial added1 added2], Rubish::Builtins.compreply
    assert_equal %w[initial added1 added2], Rubish::Builtins.get_array('COMPREPLY')
  end

  def test_function_sets_compreply_element
    execute('_elementtest() { COMPREPLY=(); COMPREPLY[0]=first; COMPREPLY[1]=second; }')
    execute('complete -F _elementtest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd ',
      point: 8,
      words: %w[testcmd],
      cword: 1
    )

    @repl.send(:call_function, '_elementtest', %w[testcmd '' testcmd])

    assert_equal %w[first second], Rubish::Builtins.compreply
    assert_equal %w[first second], Rubish::Builtins.get_array('COMPREPLY')
  end

  def test_function_iterates_comp_words
    # Use a simpler version without local to test array length
    execute('_itertest() { echo "${#COMP_WORDS[@]}" > ' + output_file + '; COMPREPLY=(); }')
    execute('complete -F _itertest testcmd')

    Rubish::Builtins.set_completion_context(
      line: 'testcmd one two three',
      point: 21,
      words: %w[testcmd one two three],
      cword: 3
    )

    @repl.send(:call_function, '_itertest', %w[testcmd three two])

    assert_equal "4\n", File.read(output_file)
  end
end
