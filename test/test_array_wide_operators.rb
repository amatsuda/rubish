# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Pattern, replacement and case operators on ${arr[@]} apply to every element
class TestArrayWideOperators < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('arr_w=(ax bx cx)')
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_aw') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_replacement_on_every_element
    assert_equal "ay by cy\n", run_and_read('echo "${arr_w[@]/x/y}"')
  end

  def test_prefix_and_suffix_removal_on_every_element
    assert_equal "x x x | a b c\n", run_and_read('echo "${arr_w[@]#?}" "|" "${arr_w[@]%x}"')
  end

  def test_case_modification_on_every_element
    assert_equal "AX BX CX Ax Bx Cx\n", run_and_read('echo "${arr_w[@]^^}" "${arr_w[@]^}"')
  end

  def test_quoted_form_keeps_one_word_per_element
    assert_equal "3\n", run_and_read('f() { echo $#; }; f "${arr_w[@]/x/y}"')
  end

  def test_positional_parameters_too
    @repl.positional_params = %w[p.txt q.txt]
    assert_equal "p q\n", run_and_read('echo "${@%.txt}"')
  end
end
