# frozen_string_literal: true

module Rubish
  module Builtins
    COMMANDS = %w[cd exit].freeze

    def self.builtin?(name)
      COMMANDS.include?(name)
    end

    def self.run(name, args)
      case name
      when 'cd'
        dir = args.first || ENV['HOME']
        Dir.chdir(dir)
        true
      when 'exit'
        code = args.first&.to_i || 0
        throw :exit, code
      else
        false
      end
    end
  end
end
