# frozen_string_literal: true

require_relative 'test_helper'

class TestTest < Test::Unit::TestCase
  def setup
    @tempdir = Dir.mktmpdir('rubish_test_test')
    @test_file = File.join(@tempdir, 'testfile.txt')
    File.write(@test_file, 'content')
    @test_dir = File.join(@tempdir, 'testdir')
    Dir.mkdir(@test_dir)
    @empty_file = File.join(@tempdir, 'empty.txt')
    File.write(@empty_file, '')
    @symlink = File.join(@tempdir, 'symlink')
    File.symlink(@test_file, @symlink)
    @older_file = File.join(@tempdir, 'older.txt')
    File.write(@older_file, 'older')
    sleep 0.01  # Ensure time difference
    @newer_file = File.join(@tempdir, 'newer.txt')
    File.write(@newer_file, 'newer')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def test_test_is_builtin
    assert Rubish::Builtins.builtin?('test')
  end

  def test_bracket_is_builtin
    assert Rubish::Builtins.builtin?('[')
  end

  # String tests
  def test_z_empty_string
    assert_equal true, Rubish::Builtins.run('test', ['-z', ''])
  end

  def test_z_nonempty_string
    assert_equal false, Rubish::Builtins.run('test', ['-z', 'hello'])
  end

  def test_n_empty_string
    assert_equal false, Rubish::Builtins.run('test', ['-n', ''])
  end

  def test_n_nonempty_string
    assert_equal true, Rubish::Builtins.run('test', ['-n', 'hello'])
  end

  # File tests
  def test_f_regular_file
    assert_equal true, Rubish::Builtins.run('test', ['-f', @test_file])
  end

  def test_f_directory
    assert_equal false, Rubish::Builtins.run('test', ['-f', @test_dir])
  end

  def test_f_nonexistent
    assert_equal false, Rubish::Builtins.run('test', ['-f', '/nonexistent'])
  end

  def test_d_directory
    assert_equal true, Rubish::Builtins.run('test', ['-d', @test_dir])
  end

  def test_d_regular_file
    assert_equal false, Rubish::Builtins.run('test', ['-d', @test_file])
  end

  def test_e_exists_file
    assert_equal true, Rubish::Builtins.run('test', ['-e', @test_file])
  end

  def test_e_exists_dir
    assert_equal true, Rubish::Builtins.run('test', ['-e', @test_dir])
  end

  def test_e_nonexistent
    assert_equal false, Rubish::Builtins.run('test', ['-e', '/nonexistent'])
  end

  def test_r_readable
    assert_equal true, Rubish::Builtins.run('test', ['-r', @test_file])
  end

  def test_w_writable
    assert_equal true, Rubish::Builtins.run('test', ['-w', @test_file])
  end

  def test_s_nonempty_file
    assert_equal true, Rubish::Builtins.run('test', ['-s', @test_file])
  end

  def test_s_empty_file
    assert_equal false, Rubish::Builtins.run('test', ['-s', @empty_file])
  end

  def test_s_nonexistent
    assert_equal false, Rubish::Builtins.run('test', ['-s', '/nonexistent'])
  end

  # String comparisons
  def test_equal_strings
    assert_equal true, Rubish::Builtins.run('test', ['foo', '=', 'foo'])
  end

  def test_equal_strings_double
    assert_equal true, Rubish::Builtins.run('test', ['foo', '==', 'foo'])
  end

  def test_unequal_strings
    assert_equal false, Rubish::Builtins.run('test', ['foo', '=', 'bar'])
  end

  def test_not_equal_strings
    assert_equal true, Rubish::Builtins.run('test', ['foo', '!=', 'bar'])
  end

  def test_not_equal_same_strings
    assert_equal false, Rubish::Builtins.run('test', ['foo', '!=', 'foo'])
  end

  # Numeric comparisons
  def test_eq_equal
    assert_equal true, Rubish::Builtins.run('test', ['5', '-eq', '5'])
  end

  def test_eq_unequal
    assert_equal false, Rubish::Builtins.run('test', ['5', '-eq', '3'])
  end

  def test_ne_unequal
    assert_equal true, Rubish::Builtins.run('test', ['5', '-ne', '3'])
  end

  def test_ne_equal
    assert_equal false, Rubish::Builtins.run('test', ['5', '-ne', '5'])
  end

  def test_lt_less
    assert_equal true, Rubish::Builtins.run('test', ['3', '-lt', '5'])
  end

  def test_lt_equal
    assert_equal false, Rubish::Builtins.run('test', ['5', '-lt', '5'])
  end

  def test_lt_greater
    assert_equal false, Rubish::Builtins.run('test', ['7', '-lt', '5'])
  end

  def test_le_less
    assert_equal true, Rubish::Builtins.run('test', ['3', '-le', '5'])
  end

  def test_le_equal
    assert_equal true, Rubish::Builtins.run('test', ['5', '-le', '5'])
  end

  def test_le_greater
    assert_equal false, Rubish::Builtins.run('test', ['7', '-le', '5'])
  end

  def test_gt_greater
    assert_equal true, Rubish::Builtins.run('test', ['7', '-gt', '5'])
  end

  def test_gt_equal
    assert_equal false, Rubish::Builtins.run('test', ['5', '-gt', '5'])
  end

  def test_gt_less
    assert_equal false, Rubish::Builtins.run('test', ['3', '-gt', '5'])
  end

  def test_ge_greater
    assert_equal true, Rubish::Builtins.run('test', ['7', '-ge', '5'])
  end

  def test_ge_equal
    assert_equal true, Rubish::Builtins.run('test', ['5', '-ge', '5'])
  end

  def test_ge_less
    assert_equal false, Rubish::Builtins.run('test', ['3', '-ge', '5'])
  end

  # Single argument
  def test_single_nonempty_arg
    assert_equal true, Rubish::Builtins.run('test', ['hello'])
  end

  def test_single_empty_arg
    assert_equal false, Rubish::Builtins.run('test', [''])
  end

  # Empty args
  def test_empty_args
    assert_equal false, Rubish::Builtins.run('test', [])
  end

  # Negation
  def test_negation_true_becomes_false
    assert_equal false, Rubish::Builtins.run('test', ['!', 'hello'])
  end

  def test_negation_false_becomes_true
    assert_equal true, Rubish::Builtins.run('test', ['!', ''])
  end

  def test_negation_with_operator
    assert_equal true, Rubish::Builtins.run('test', ['!', 'foo', '=', 'bar'])
  end

  # Bracket syntax
  def test_bracket_with_closing_bracket
    assert_equal true, Rubish::Builtins.run('[', ['-f', @test_file, ']'])
  end

  def test_bracket_string_comparison
    assert_equal true, Rubish::Builtins.run('[', ['foo', '=', 'foo', ']'])
  end

  def test_bracket_numeric_comparison
    assert_equal true, Rubish::Builtins.run('[', ['5', '-eq', '5', ']'])
  end

  # Symlink tests
  def test_L_symlink
    assert_equal true, Rubish::Builtins.run('test', ['-L', @symlink])
  end

  def test_L_regular_file
    assert_equal false, Rubish::Builtins.run('test', ['-L', @test_file])
  end

  def test_h_symlink
    assert_equal true, Rubish::Builtins.run('test', ['-h', @symlink])
  end

  def test_h_regular_file
    assert_equal false, Rubish::Builtins.run('test', ['-h', @test_file])
  end

  def test_L_nonexistent
    assert_equal false, Rubish::Builtins.run('test', ['-L', '/nonexistent'])
  end

  # Block and character device tests
  def test_b_regular_file
    assert_equal false, Rubish::Builtins.run('test', ['-b', @test_file])
  end

  def test_c_regular_file
    assert_equal false, Rubish::Builtins.run('test', ['-c', @test_file])
  end

  # Note: /dev/null is a character device on Unix systems
  def test_c_dev_null
    skip unless File.exist?('/dev/null')
    assert_equal true, Rubish::Builtins.run('test', ['-c', '/dev/null'])
  end

  # Socket test
  def test_S_regular_file
    assert_equal false, Rubish::Builtins.run('test', ['-S', @test_file])
  end

  # Pipe test
  def test_p_regular_file
    assert_equal false, Rubish::Builtins.run('test', ['-p', @test_file])
  end

  # Terminal test
  def test_t_stdout_not_tty
    # In test context, stdout is usually not a terminal
    assert_equal false, Rubish::Builtins.run('test', ['-t', '1'])
  end

  # Permission bit tests
  def test_O_owned_file
    assert_equal true, Rubish::Builtins.run('test', ['-O', @test_file])
  end

  def test_G_owned_file
    assert_equal true, Rubish::Builtins.run('test', ['-G', @test_file])
  end

  def test_u_no_setuid
    assert_equal false, Rubish::Builtins.run('test', ['-u', @test_file])
  end

  def test_g_no_setgid
    assert_equal false, Rubish::Builtins.run('test', ['-g', @test_file])
  end

  def test_k_no_sticky
    assert_equal false, Rubish::Builtins.run('test', ['-k', @test_file])
  end

  # String comparison with < and >
  def test_string_less_than
    assert_equal true, Rubish::Builtins.run('test', ['abc', '<', 'abd'])
  end

  def test_string_less_than_false
    assert_equal false, Rubish::Builtins.run('test', ['abd', '<', 'abc'])
  end

  def test_string_greater_than
    assert_equal true, Rubish::Builtins.run('test', ['abd', '>', 'abc'])
  end

  def test_string_greater_than_false
    assert_equal false, Rubish::Builtins.run('test', ['abc', '>', 'abd'])
  end

  # File comparison tests
  def test_nt_newer_than
    assert_equal true, Rubish::Builtins.run('test', [@newer_file, '-nt', @older_file])
  end

  def test_nt_older_than
    assert_equal false, Rubish::Builtins.run('test', [@older_file, '-nt', @newer_file])
  end

  def test_nt_nonexistent
    assert_equal false, Rubish::Builtins.run('test', [@test_file, '-nt', '/nonexistent'])
  end

  def test_ot_older_than
    assert_equal true, Rubish::Builtins.run('test', [@older_file, '-ot', @newer_file])
  end

  def test_ot_newer_than
    assert_equal false, Rubish::Builtins.run('test', [@newer_file, '-ot', @older_file])
  end

  def test_ot_nonexistent
    assert_equal false, Rubish::Builtins.run('test', [@test_file, '-ot', '/nonexistent'])
  end

  def test_ef_same_file
    # Create a hard link
    hard_link = File.join(@tempdir, 'hardlink')
    File.link(@test_file, hard_link)
    assert_equal true, Rubish::Builtins.run('test', [@test_file, '-ef', hard_link])
  end

  def test_ef_different_files
    assert_equal false, Rubish::Builtins.run('test', [@test_file, '-ef', @empty_file])
  end

  def test_ef_nonexistent
    assert_equal false, Rubish::Builtins.run('test', [@test_file, '-ef', '/nonexistent'])
  end

  # Compound expression tests with -a (AND)
  def test_and_both_true
    assert_equal true, Rubish::Builtins.run('test', ['-f', @test_file, '-a', '-r', @test_file])
  end

  def test_and_first_false
    assert_equal false, Rubish::Builtins.run('test', ['-d', @test_file, '-a', '-r', @test_file])
  end

  def test_and_second_false
    assert_equal false, Rubish::Builtins.run('test', ['-f', @test_file, '-a', '-d', @test_file])
  end

  def test_and_both_false
    assert_equal false, Rubish::Builtins.run('test', ['-d', @test_file, '-a', '-d', @test_file])
  end

  # Compound expression tests with -o (OR)
  def test_or_both_true
    assert_equal true, Rubish::Builtins.run('test', ['-f', @test_file, '-o', '-r', @test_file])
  end

  def test_or_first_true
    assert_equal true, Rubish::Builtins.run('test', ['-f', @test_file, '-o', '-d', @test_file])
  end

  def test_or_second_true
    assert_equal true, Rubish::Builtins.run('test', ['-d', @test_file, '-o', '-f', @test_file])
  end

  def test_or_both_false
    assert_equal false, Rubish::Builtins.run('test', ['-d', @test_file, '-o', '-d', @test_file])
  end

  # Compound expression precedence: -a binds tighter than -o
  def test_compound_precedence
    # -f file -o -d file -a -d dir should be: (-f file) -o ((-d file) -a (-d dir))
    # = true -o (false -a true) = true -o false = true
    assert_equal true, Rubish::Builtins.run('test', ['-f', @test_file, '-o', '-d', @test_file, '-a', '-d', @test_dir])
  end

  # Negation with compound
  def test_negation_with_and
    assert_equal true, Rubish::Builtins.run('test', ['!', '-d', @test_file, '-a', '-f', @test_file])
  end

  # Variable set tests (-v)
  def test_v_set_variable
    ENV['TEST_VAR'] = 'value'
    assert_equal true, Rubish::Builtins.run('test', ['-v', 'TEST_VAR'])
  ensure
    ENV.delete('TEST_VAR')
  end

  def test_v_unset_variable
    ENV.delete('NONEXISTENT_VAR')
    assert_equal false, Rubish::Builtins.run('test', ['-v', 'NONEXISTENT_VAR'])
  end

  def test_v_empty_variable
    # Variable set to empty string should still return true
    ENV['EMPTY_VAR'] = ''
    assert_equal true, Rubish::Builtins.run('test', ['-v', 'EMPTY_VAR'])
  ensure
    ENV.delete('EMPTY_VAR')
  end

  def test_v_with_bracket_syntax
    ENV['BRACKET_VAR'] = 'test'
    assert_equal true, Rubish::Builtins.run('[', ['-v', 'BRACKET_VAR', ']'])
  ensure
    ENV.delete('BRACKET_VAR')
  end

  def test_v_with_negation
    ENV.delete('MISSING_VAR')
    assert_equal true, Rubish::Builtins.run('test', ['!', '-v', 'MISSING_VAR'])
  end

  def test_v_negation_set_var
    ENV['PRESENT_VAR'] = 'exists'
    assert_equal false, Rubish::Builtins.run('test', ['!', '-v', 'PRESENT_VAR'])
  ensure
    ENV.delete('PRESENT_VAR')
  end

  def test_v_with_and
    ENV['VAR1'] = 'a'
    ENV['VAR2'] = 'b'
    assert_equal true, Rubish::Builtins.run('test', ['-v', 'VAR1', '-a', '-v', 'VAR2'])
  ensure
    ENV.delete('VAR1')
    ENV.delete('VAR2')
  end

  def test_v_with_and_one_unset
    ENV['VAR_SET'] = 'value'
    ENV.delete('VAR_UNSET')
    assert_equal false, Rubish::Builtins.run('test', ['-v', 'VAR_SET', '-a', '-v', 'VAR_UNSET'])
  ensure
    ENV.delete('VAR_SET')
  end

  def test_v_with_or
    ENV['VAR_PRESENT'] = 'value'
    ENV.delete('VAR_ABSENT')
    assert_equal true, Rubish::Builtins.run('test', ['-v', 'VAR_PRESENT', '-o', '-v', 'VAR_ABSENT'])
  ensure
    ENV.delete('VAR_PRESENT')
  end

  def test_v_both_unset_or
    ENV.delete('UNSET1')
    ENV.delete('UNSET2')
    assert_equal false, Rubish::Builtins.run('test', ['-v', 'UNSET1', '-o', '-v', 'UNSET2'])
  end

  # Help documentation test
  def test_help_has_new_options
    help = Rubish::Builtins::BUILTIN_HELP['test']
    assert_not_nil help
    assert help[:options].key?('-L file')
    assert help[:options].key?('-b file')
    assert help[:options].key?('-S file')
    assert help[:options].key?('f1 -nt f2')
    assert help[:options].key?('e1 -a e2')
  end

  def test_help_has_v_option
    help = Rubish::Builtins::BUILTIN_HELP['test']
    assert_not_nil help
    assert help[:options].key?('-v varname')
  end
end
