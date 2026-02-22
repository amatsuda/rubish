# Rubish

A UNIX shell written in pure Ruby.

Shell syntax is parsed and compiled to Ruby code, then executed by the Ruby VM.

## Concept

### Fully Bash-compatible

Rubish supports all the features of bash, and the shell syntax is fully compatible. You can run your existing bash scripts without modification. If you found any bash script that doesn't work in rubish, we consider it a bug, so please report it!

### Deep Ruby integration

Rubish is not just a shell implemented in Ruby, but a shell that deeply integrates Ruby. You can seamlessly mix shell commands and Ruby code, and even use Ruby's powerful features like blocks, iterators, and libraries in your shell scripts.

## Installation

### Homebrew (macOS)

```sh
brew tap amatsuda/rubish
brew install --HEAD rubish

```

### From source

```sh
git clone https://github.com/amatsuda/rubish.git
cd rubish
bundle install
bundle exec bin/rubish
```

## Usage

Start an interactive shell:

```sh
rubish
```

Run a single command:

```sh
rubish -c 'echo hello'
```

Run a script:

```sh
rubish script.sh
```

Or you can even use this as a login shell!


### Set as login shell

```sh
echo "$(which rubish)" | sudo tee -a /etc/shells
chsh -s "$(which rubish)"
```

## Features beyond Bash

### Ruby conditions

Use Ruby expressions as conditions in `if`, `while`, and `until` by wrapping them in `{ }`. Shell variables are automatically bound as local variables in the Ruby expression:

```sh
COUNT=5
if { count.to_i > 3 }
  echo 'count is greater than 3'
end

while { count.to_i > 0 }
  echo $COUNT
  COUNT=$((COUNT - 1))
done
```

### Ruby method call style

Commands can be invoked using Ruby method call syntax with parentheses, in addition to the traditional UNIX style with spaces:

```sh
# These are equivalent:
ls -la
ls('-la')

# Arguments can be passed as method arguments:
cat(file.txt)
grep('pattern', file.txt)
```

### Method chaining

Commands can be chained with Ruby methods using dot notation, forming a pipeline:

```sh
# Equitalent to `ls | sort`
ls.sort

# Equivalent to `cat file.txt | grep error`
cat(file.txt).grep(/error/)
```

### Ruby iterator blocks

Ruby iterator methods (`.each`, `.map`, `.select`, `.detect`) can take blocks to process command output line by line:

```sh
ls.each { |f| puts f.upcase }
cat(file.txt).map { |line| line.strip }
ls.select { it.end_with?('.rb') }
```

### Inline Ruby evaluation

Any line starting with a capital letter is evaluated as Ruby code directly. This means you can use Ruby classes, methods, and expressions right from the shell prompt without any special syntax:

```
rubish$ Time.now
=> 2025-01-01 12:00:00 +0900

rubish$ Dir.glob('*.rb').sort
=> ["Gemfile", "Rakefile"]

rubish$ ENV['HOME']
=> "/Users/you"
```

### Ruby array and regexp literals

Ruby array literals can be used directly in shell context. Rubish distinguishes them from glob patterns like `[a-z]` automatically:

```
rubish$ [1, 2, 3].map { |x| x * x }
=> [1, 4, 9]
```
### Lambda expressions

You can execute any Ruby code by surrounding it with a lambda expression (`-> { }`):

```
rubish$ -> { 2 ** 10 }
=> 1024
```

### Ruby-style function definitions

In addition to the standard shell function syntax, rubish supports Ruby-style `def...end` with named parameters and splat args:

```sh
def greet(name)
  echo "Hello, $name"
end

def log(level, *messages)
  echo "[$level] $messages"
end

greet world    # => Hello, world
```

### Custom Ruby prompts

Define your prompt as a Ruby function for full programmatic control. The function is called on every prompt render, so it can include dynamic content:

```sh
def rubish_prompt
  branch = `git branch --show-current 2>/dev/null`.strip
  dir = Dir.pwd.sub(ENV['HOME'], '~')
  "\e[36m#{dir}\e[0m \e[33m#{branch}\e[0m $ "
end

def rubish_right_prompt
  Time.now.strftime('%H:%M:%S')
end
```

You can also use the traditional `PS1`/`RPROMPT` variables with bash (`\X`) or zsh (`%X`) escape codes.

### Lazy loading

Slow shell initializations (e.g., `rbenv init`, `nvm`, `pyenv`) can be deferred to a background thread using `lazy_load`. The block runs immediately in the background, and its result (a string of shell code) is applied before the next prompt. This keeps shell startup instant:

```sh
# In ~/.rubishrc
lazy_load {
  `rbenv init - --no-rehash bash`
}

lazy_load {
  `nodenv init - bash`
}
```

Multiple `lazy_load` blocks run in parallel. By the time you type your first command, they're usually done.

### Restricted mode

Running `rubish -r` disables all Ruby integration features (inline evaluation, lambdas, blocks, Ruby conditions, and array literals) for executing untrusted scripts safely. Only standard shell syntax is allowed.

### Zsh compatibility

In addition to full Bash compatibility, rubish also supports zsh-style features:

- `setopt`/`unsetopt`
- `compdef`/`compinit`
- `autoload` with `fpath`
- `%X` prompt codes and `RPROMPT`/`RPS1`
- Abbreviated path expansion: type `a/c/a<Tab>` and it expands to `app/controllers/application_controller.rb`

### Configuration files

**Login shells** load (in order):
1. `/etc/profile`
2. `~/.config/rubish/profile` or `~/.rubish_profile` (or `~/.bash_profile` / `~/.bash_login` / `~/.profile`)

**Interactive shells** load:
1. `~/.config/rubish/config` or `~/.rubishrc` (or `~/.bashrc`)
2. `./.rubishrc` (project-local)

**Logout**:
1. `~/.config/rubish/logout` or `~/.rubish_logout` (or `~/.bash_logout`)

## Builtins

| Category | Commands |
|----------|----------|
| Directory | `cd`, `pwd`, `pushd`, `popd`, `dirs` |
| I/O | `echo`, `printf`, `read`, `mapfile`, `readarray` |
| Variables | `export`, `declare`, `typeset`, `readonly`, `unset`, `local`, `shift`, `set` |
| Process | `exit`, `logout`, `exec`, `kill`, `wait`, `times` |
| Job control | `jobs`, `fg`, `bg`, `disown`, `suspend` |
| Functions | `function`, `return`, `caller` |
| Aliases | `alias`, `unalias` |
| History | `history`, `fc` |
| Execution | `eval`, `source`, `.`, `command`, `builtin` |
| Testing | `test`, `[`, `[[`, `(( ))`, `let` |
| Control | `break`, `continue`, `trap` |
| Completion | `complete`, `compgen`, `compopt`, `bind` |
| Config | `shopt`, `setopt`, `unsetopt` |
| Info | `help`, `type`, `which`, `hash` |
| Other | `true`, `false`, `:`, `getopts`, `umask`, `ulimit`, `enable` |

## Development

```sh
bundle install
bundle exec rake test
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/amatsuda/rubish.

## License

MIT
