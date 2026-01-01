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
end
