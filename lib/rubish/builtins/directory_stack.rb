# frozen_string_literal: true

module Rubish
  module Builtins
    def pushd(args)
      # pushd [-n] [+N | -N | dir]
      # -n: Suppress the normal change of directory; only manipulate the stack
      # +N: Rotate the stack so that the Nth directory (counting from left, starting at 0) is at the top
      # -N: Rotate the stack so that the Nth directory (counting from right, starting at 0) is at the top
      # dir: Push dir onto the stack and cd to it

      no_cd = false
      remaining_args = []

      args.each do |arg|
        if arg == '-n'
          no_cd = true
        else
          remaining_args << arg
        end
      end

      if remaining_args.empty?
        # Swap top two directories
        if @state.dir_stack.empty?
          puts 'pushd: no other directory'
          return false
        end
        current = Dir.pwd
        target = @state.dir_stack.shift
        @state.dir_stack.unshift(current)
        unless no_cd
          begin
            Dir.chdir(target)
            notify_terminal_of_cwd
          rescue Errno::ENOENT => e
            puts "pushd: #{e.message}"
            return false
          end
        end
        print_dir_stack
        true
      elsif remaining_args.first =~ /^[+-]\d+$/
        # Stack rotation: +N or -N
        arg = remaining_args.first
        n = arg[1..].to_i
        full_stack = [Dir.pwd] + @state.dir_stack

        if n >= full_stack.length
          puts "pushd: #{arg}: directory stack index out of range"
          return false
        end

        if arg.start_with?('+')
          # +N: rotate left by N positions
          rotated = full_stack.rotate(n)
        else
          # -N: count from right (end of stack)
          # -0 is last element, -1 is second to last, etc.
          index = full_stack.length - 1 - n
          if index < 0
            puts "pushd: #{arg}: directory stack index out of range"
            return false
          end
          rotated = full_stack.rotate(index)
        end

        target = rotated.first
        @state.dir_stack = rotated[1..]

        unless no_cd
          begin
            Dir.chdir(target)
            notify_terminal_of_cwd
          rescue Errno::ENOENT => e
            puts "pushd: #{e.message}"
            return false
          end
        end
        print_dir_stack
        true
      else
        # Push directory
        dir = remaining_args.first
        dir = File.expand_path(dir)
        current = Dir.pwd

        unless File.directory?(dir)
          puts "pushd: #{dir}: No such file or directory"
          return false
        end

        @state.dir_stack.unshift(current)
        unless no_cd
          begin
            Dir.chdir(dir)
            notify_terminal_of_cwd
          rescue Errno::ENOENT => e
            puts "pushd: #{e.message}"
            return false
          end
        end
        print_dir_stack
        true
      end
    end

    def popd(args)
      # popd [-n] [+N | -N]
      # -n: Suppress the normal change of directory; only manipulate the stack
      # +N: Remove the Nth directory (counting from left, starting at 0)
      # -N: Remove the Nth directory (counting from right, starting at 0)

      no_cd = false
      index_arg = nil

      args.each do |arg|
        if arg == '-n'
          no_cd = true
        elsif arg =~ /^[+-]\d+$/
          index_arg = arg
        else
          puts "popd: #{arg}: invalid argument"
          return false
        end
      end

      if @state.dir_stack.empty? && index_arg.nil?
        puts 'popd: directory stack empty'
        return false
      end

      full_stack = [Dir.pwd] + @state.dir_stack

      if index_arg
        n = index_arg[1..].to_i

        if index_arg.start_with?('+')
          # +N: remove Nth element from left (0 = current dir)
          index = n
        else
          # -N: remove Nth element from right (0 = last element)
          index = full_stack.length - 1 - n
        end

        if index < 0 || index >= full_stack.length
          puts "popd: #{index_arg}: directory stack index out of range"
          return false
        end

        if index == 0
          # Removing current directory - need to cd to next
          if full_stack.length < 2
            puts 'popd: directory stack empty'
            return false
          end
          target = full_stack[1]
          @state.dir_stack = full_stack[2..] || []
          unless no_cd
            begin
              Dir.chdir(target)
              notify_terminal_of_cwd
            rescue Errno::ENOENT => e
              puts "popd: #{e.message}"
              return false
            end
          end
        else
          # Removing from stack (not current dir)
          full_stack.delete_at(index)
          @state.dir_stack = full_stack[1..] || []
        end
      else
        # Default: pop top of stack and cd there
        if @state.dir_stack.empty?
          puts 'popd: directory stack empty'
          return false
        end

        target = @state.dir_stack.shift
        unless no_cd
          begin
            Dir.chdir(target)
            notify_terminal_of_cwd
          rescue Errno::ENOENT => e
            puts "popd: #{e.message}"
            return false
          end
        end
      end

      print_dir_stack
      true
    end

    def dirs(args)
      print_dir_stack
      true
    end

    def print_dir_stack
      stack = [Dir.pwd] + @state.dir_stack
      puts stack.map { |d| d.sub(ENV['HOME'], '~') }.join(' ')
    end

    def clear_dir_stack
      @state.dir_stack.clear
    end
  end
end
