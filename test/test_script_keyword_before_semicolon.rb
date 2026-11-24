# frozen_string_literal: true

require_relative 'test_helper'

# A closing keyword glued to a `;` (`esac;`, `fi;`) still closes its structure in a script
class TestScriptKeywordBeforeSemicolon < Test::Unit::TestCase
  def test_no_unclosed_warning
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s.sh", "case x in x) echo a;; esac; echo b\nif true; then echo c; fi; echo d\n")
      out = IO.popen([exe, "#{dir}/s.sh", err: %i[child out]], chdir: dir, &:read)
      assert_equal "a\nb\nc\nd\n", out
    end
  end
end
