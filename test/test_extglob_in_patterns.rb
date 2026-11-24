# frozen_string_literal: true

require_relative 'test_helper'

# extglob patterns work in case patterns, in [[ == ]] and as globs
class TestExtglobInPatterns < Test::Unit::TestCase
  def run_script(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s.sh", script)
      IO.popen([exe, "#{dir}/s.sh", err: %i[child out]], chdir: dir, &:read)
    end
  end

  def test_case_patterns
    assert_equal "txt\nopt\nat\n", run_script("shopt -s extglob\ncase foo.txt in !(*.txt)) echo not;; *) echo txt;; esac\ncase x in ?(x|y)) echo opt;; esac\ncase ab in @(a|ab)) echo at;; esac\n")
  end

  def test_negation_in_conditional
    assert_equal "neg\nat\n", run_script("shopt -s extglob\n[[ aXb == a!(X)b ]] || echo neg\n[[ abc == @(abc|def) ]] && echo at\n")
  end

  def test_globs
    assert_equal "b.py c.txt\na.rb b.py\nab abb abbb\nab\n", run_script("shopt -s extglob\ntouch a.rb b.py c.txt ab abb abbb\necho !(*.rb|ab*|*.sh)\necho *.@(rb|py)\necho a*(b)\necho a?(b)\n")
  end
end
