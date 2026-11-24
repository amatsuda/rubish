# frozen_string_literal: true

require_relative 'test_helper'

# The pattern and replacement of ${var/pattern/replacement} are words:
# variables expand in them and quoted parts match literally
class TestParamSubstWordExpansion < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_variables_in_pattern_and_replacement_on_the_fast_path
    assert_equal "hehellolo heQlo heRlo\n", run_shell('x=hello; p=l; echo ${x/l/$x} ${x/$p/Q} ${x/"$p"/R}')
  end

  def test_variables_in_pattern_and_replacement_in_generated_code
    assert_equal "hehellolo heQlo\n", run_shell('x=hello; p=l; /bin/echo ${x/l/$x} ${x/$p/Q}')
  end

  def test_variables_in_an_assignment
    assert_equal "hehellolo\n", run_shell('x=hello; y=${x/l/$x}; echo $y')
  end

  def test_quoted_parts
    assert_equal "he'lo he\"lo\n", run_shell(%q{x=hello; echo ${x/l/"'"} ${x/l/'"'}})
    assert_equal "s.txt star.txt\n", run_shell(%q{x='*.txt'; echo "${x/'*'/s}" ${x/\*/star}})
  end

  def test_pattern_from_a_variable_is_a_pattern
    assert_equal "Xtxt\n", run_shell(%q{x=file.txt; p='*.'; echo ${x/$p/X}})
  end
end
