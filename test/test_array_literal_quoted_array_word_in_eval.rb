# frozen_string_literal: true

require_relative 'test_helper'

# "${a[@]}" inside a compound assignment keeps one element per element, in eval and sourced files too
class TestArrayLiteralQuotedArrayWordInEval < Test::Unit::TestCase
  def test_eval_and_source
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s.sh", "c=(\"${a[@]}\" x)\n")
      out = IO.popen([exe, '-c', %q{a=(1 'two words' 3); eval 'b=("${a[@]}")'; echo "${#b[@]} ${b[1]}"; . ./s.sh; echo "${#c[@]} ${c[1]}"}, err: %i[child out]], chdir: dir, &:read)
      assert_equal "3 two words\n4 two words\n", out
    end
  end
end
