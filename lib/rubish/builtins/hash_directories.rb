# frozen_string_literal: true

module Rubish
  module Builtins
    def hash(args)
      # hash [-lr] [-p path] [-dt] [name ...]
      # -r: forget all cached paths
      # -d: named directories (zsh) or forget cached path (bash)
      # -l: list in reusable format
      # -p path: cache name with given path
      # -t: print cached path for each name
      #
      # zsh-style named directories (hash -d):
      #   hash -d name=path  - define named directory (~name expands to path)
      #   hash -d name       - show path for named directory
      #   hash -d            - list all named directories

      if args.empty?
        print_command_hash
        return true
      end

      # Parse options
      clear_all = false
      named_dir_mode = false
      delete_mode = false
      list_mode = false
      print_mode = false
      set_path = nil
      names = []
      i = 0

      while i < args.length
        arg = args[i]

        if arg == '-r' && names.empty?
          clear_all = true
          i += 1
        elsif arg == '-d' && names.empty?
          named_dir_mode = true
          i += 1
        elsif arg == '-l' && names.empty?
          list_mode = true
          i += 1
        elsif arg == '-t' && names.empty?
          print_mode = true
          i += 1
        elsif arg == '-p' && names.empty? && i + 1 < args.length
          set_path = args[i + 1]
          i += 2
        elsif arg.start_with?('-') && names.empty?
          # Handle combined flags
          arg[1..].each_char do |c|
            case c
            when 'r' then clear_all = true
            when 'd' then named_dir_mode = true
            when 'l' then list_mode = true
            when 't' then print_mode = true
            else
              puts "hash: -#{c}: invalid option"
              return false
            end
          end
          i += 1
        else
          names << arg
          i += 1
        end
      end

      # Handle named directories mode (zsh-style hash -d)
      if named_dir_mode
        return hash_named_directories(names, list_mode)
      end

      # Handle -r (clear all)
      if clear_all
        @state.command_hash.clear
        return true
      end

      # Handle -l (list mode) with no names
      if list_mode && names.empty?
        @state.command_hash.each do |name, path|
          puts "hash -p #{path} #{name}"
        end
        return true
      end

      # Handle names
      all_found = true

      if names.empty? && !set_path
        print_command_hash
        return true
      end

      names.each do |name|
        if delete_mode
          # Forget cached path
          if @state.command_hash.key?(name)
            @state.command_hash.delete(name)
          else
            puts "hash: #{name}: not found"
            all_found = false
          end
        elsif print_mode
          # Print cached path
          if @state.command_hash.key?(name)
            puts @state.command_hash[name]
          else
            # Try to find and cache
            path = find_in_path(name)
            if path
              @state.command_hash[name] = path
              puts path
            else
              puts "hash: #{name}: not found"
              all_found = false
            end
          end
        elsif set_path
          # Set specific path
          @state.command_hash[name] = set_path
        else
          # Cache the command
          path = find_in_path(name)
          if path
            @state.command_hash[name] = path
          else
            puts "hash: #{name}: not found"
            all_found = false
          end
        end
      end

      all_found
    end

    def hash_lookup(name)
      @state.command_hash[name]
    end

    def hash_store(name, path)
      @state.command_hash[name] = path
    end

    def hash_delete(name)
      @state.command_hash.delete(name)
    end

    def clear_hash
      @state.command_hash.clear
    end

    # Handle -d option: named directories (zsh) or delete from hash (bash)
    # - hash -d           → list all named directories (zsh)
    # - hash -d name=path → define named directory (zsh)
    # - hash -d name      → if name is in command_hash, delete it (bash)
    #                       if name is a named directory, show path (zsh)
    #                       otherwise, error
    def hash_named_directories(names, list_mode = false)
      # No names: list all named directories
      if names.empty?
        if Builtins.named_directories.empty?
          # Don't print anything when empty (zsh behavior)
          return true
        end
        Builtins.named_directories.each do |name, path|
          if list_mode
            puts "hash -d #{name}=#{path}"
          else
            puts "#{name}=#{path}"
          end
        end
        return true
      end

      all_success = true

      # Process each name
      names.each do |arg|
        if arg.include?('=')
          # Define named directory: name=path (zsh-style)
          name, path = arg.split('=', 2)
          if name.empty?
            puts "hash: invalid argument: #{arg}"
            all_success = false
            next
          end
          # Expand ~ in path
          path = File.expand_path(path) if path.start_with?('~')
          Builtins.named_directories[name] = path
        elsif @state.command_hash.key?(arg)
          # Bash-style: delete from command hash
          @state.command_hash.delete(arg)
        elsif Builtins.named_directories.key?(arg)
          # zsh-style: show named directory path
          puts Builtins.named_directories[arg]
        else
          # Not found in either
          puts "hash: #{arg}: not found"
          all_success = false
        end
      end

      all_success
    end

    # Get a named directory path
    def get_named_directory(name)
      Builtins.named_directories[name]
    end

    # Set a named directory
    def set_named_directory(name, path)
      Builtins.named_directories[name] = path
    end

    # Remove a named directory
    def remove_named_directory(name)
      Builtins.named_directories.delete(name)
    end

    # Expand ~name to the named directory path
    # Returns nil if not a named directory
    def expand_named_directory(str)
      return nil unless str.start_with?('~')
      return nil if str == '~' || str.start_with?('~/')

      # Extract the name part (after ~ and before / or end)
      if str.include?('/')
        name = str[1...str.index('/')]
        rest = str[str.index('/')..]
      else
        name = str[1..]
        rest = ''
      end

      return nil if name.empty?

      # Check for named directory
      if Builtins.named_directories.key?(name)
        Builtins.named_directories[name] + rest
      else
        nil  # Not a named directory, let normal expansion handle it
      end
    end

    private

    def print_command_hash
      if @state.command_hash.empty?
        puts 'hash: hash table empty'
      else
        @state.command_hash.each { |name, path| puts "#{name}=#{path}" }
      end
    end
  end
end
