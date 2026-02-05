# frozen_string_literal: true

require_relative 'lib/rubish/version'

Gem::Specification.new do |spec|
  spec.name = 'rubish-gem'
  spec.version = Rubish::VERSION
  spec.authors = ['Akira Matsuda']
  spec.email = ['ronnie@dio.jp']

  spec.summary = 'rubish'
  spec.description = 'Just a rubish'
  spec.homepage = 'https://github.com/amatsuda/rubish'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.5.0'

  spec.metadata['homepage_uri'] = spec.metadata['source_code_uri'] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
end
