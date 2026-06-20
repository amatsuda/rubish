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
bundle exec exe/rubish
```

`bin/rubish` is a small bash launcher that finds a usable Ruby on its own (probes `~/.rbenv/shims/ruby`, `/opt/homebrew/bin/ruby`, `/usr/local/bin/ruby`, system Ruby; honors `$ECHOES_RUBY`, falling back to `$RUBY` for back-compat). Use it when bundler isn't around — for example as a login shell, from a `.app` bundle, or anywhere `PATH` may be minimal:

```sh
./bin/rubish
ECHOES_RUBY=/opt/homebrew/opt/ruby@3.4/bin/ruby ./bin/rubish   # explicit override
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

Commands can be chained with Ruby methods using dot notation, forming a pipeline. The chain has to be *opened* by a parenthesized call, an array literal, or a block — once you're in chain context, subsequent methods can be bare:

```sh
# Equivalent to `ls | sort`
ls().sort

# Equivalent to `ls | sort | uniq`
ls().sort.uniq

# Equivalent to `cat file.txt | grep error`
cat(file.txt).grep(/error/)

# Chains can be combined with blocks (see "Ruby iterator blocks" below)
ls.select { it.end_with?('.rb') }.each { |f| puts f.upcase }
```

The first segment needs the parens because bare `cmd.method` is ambiguous with paths and dotted filenames (`./script.sh`, `file.tar.gz`) — once `()` confirms a method-call form, the lexer knows it's safe to chain.

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

Multi-line blocks work too — rubish detects unfinished Ruby (open `do`, missing `end`, unterminated strings, etc.) and prompts for continuation lines, both at the interactive prompt and inside sourced rcfiles. Only single-line interactive expressions get the IRB-style `=> …` value printed; multi-line blocks and sourced statements run silently for their side effects.

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

### Tab completion

Rubish tab-completes most commands out of the box, with no per-tool setup files to install. The completer derives subcommands and flags from each tool's own `--help` output, on demand:

```
rubish$ git <Tab>             # add  branch  checkout  clone  commit  …
rubish$ gh pr <Tab>           # checkout  close  create  diff  edit  list  …
rubish$ rails generate <Tab>  # scaffold  model  controller  channel  mailer  …
rubish$ kubectl get <Tab>     # pods  services  deployments  …
rubish$ cargo build --<Tab>   # --release  --target  --verbose  …
```

It walks arbitrarily deep — `rails generate scaffold --<Tab>` parses scaffold's own flags, `aws s3 cp --<Tab>` reaches AWS sub-sub-commands, and so on.

How it stays correct, fast, and side-effect-free:

- For a list of well-known tools (`gem`, `brew`, `cargo`, `aws`, `npm`, `gh`, `kubectl`, `pyenv`, `rbenv`, `launchctl`, `composer`, `hg`, …) rubish curates the right help invocation (`gem help commands`, `cargo --list`, `launchctl help`, etc.), so the cleanest output is used. For anything else it falls back to `<cmd> --help` then `<cmd> -h`.
- Each result is cached for 30 minutes; repeat `<Tab>`s against the same chain are instant.
- On macOS the help command runs inside a `sandbox-exec` profile with no network access and writes restricted to `/tmp`. Completing on an unfamiliar binary can never modify your filesystem — `touch help` won't accidentally create a file.
- When zsh has a `_<cmd>` completion file in `$fpath`, rubish reads it too — improving completion for tools whose own `--help` is sparse.

Other completion features:

- **Inline auto-suggestion** (fish style) is on by default: as you type, the most likely completion appears in dim text after the cursor — press `<Right>` to accept it. `<Tab>` opens the full popup; see [Completion dialog colors](#completion-dialog-colors) to style it.
- **Abbreviated path completion** (zsh style): `a/c/a<Tab>` expands to `app/controllers/application_controller.rb` — each component matches by prefix.
- **Slow help commands**: framework CLIs like `rails` boot their full app just to print `--help`, which may exceed the default 5-second timeout. Bump it via `RUBISH_HELP_TIMEOUT=10`.
- **Debugging**: `RUBISH_DEBUG_COMPLETION=1` prints each help-command invocation, its duration, and whether it produced parseable output on stderr.

Bash- and zsh-style programmable completion (`complete -F`, `compgen`, `compdef`, `compinit`, `autoload`) is supported too, for tools where the auto-help path isn't enough. Existing completion scripts Just Work.

### Completion dialog colors

Rubish uses Reline's inline completion dialog (the fish-style suggestions popup) for tab-completion. Its colors are configured via [`Reline::Face`](https://docs.ruby-lang.org/en/master/Reline/Face.html). Drop a regular Ruby block in your rcfile:

```ruby
# In ~/.rubishrc or ~/.config/rubish/config
Reline::Face.config(:completion_dialog) do |conf|
  conf.define :default,   foreground: :cyan,  background: :black
  conf.define :enhanced,  foreground: :black, background: :cyan, style: :bold
  conf.define :scrollbar, foreground: :white, background: :black
end
```

The three face names map to different parts of the dialog: `:default` for the unselected rows, `:enhanced` for the currently highlighted row, and `:scrollbar` for the scrollbar (visible when results overflow the popup). Colors can be a Reline symbol (`:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:white`, plus `:bright_*` / `:gray` variants) or a hex truecolor string like `'#abcdef'`. `:style` accepts `:bold`, `:faint`, `:italicized`, `:underlined`, `:blinking`, `:negative`, `:concealed`, `:crossed_out` — or an array of those for multiple effects.

This works because rubish's inline Ruby evaluation handles multi-line blocks (see [Inline Ruby evaluation](#inline-ruby-evaluation)), so the natural `do … end` form is fine in both rcfiles and at the interactive prompt — no need for one-line reformatting.

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
- Abbreviated path expansion (see [Tab completion](#tab-completion))

### Configuration files

**Login shells** load (in order):
1. `/etc/profile`
2. `~/.config/rubish/profile` or `~/.rubish_profile` (or `~/.bash_profile` / `~/.bash_login` / `~/.profile`)

**Interactive shells** load:
1. `~/.config/rubish/config` or `~/.rubishrc` (or `~/.bashrc`)
2. `./.rubishrc` (project-local)

**Logout**:
1. `~/.config/rubish/logout` or `~/.rubish_logout` (or `~/.bash_logout`)

## Embedding in a Ruby program

Rubish exposes a public API so other Ruby programs (terminal emulators, IDE plugins, GUI front-ends) can drive a rubish session in-process — no fork+exec, no JSON serialization, just method calls. The sibling [Echoes](https://github.com/amatsuda/echoes) terminal emulator uses this to render syntax-highlighted prompts and decide command-execution shape ahead of time.

```ruby
require 'rubish'

repl = Rubish::REPL.new(login_shell: true)

# Run interactively (default).
repl.run

# Or drive it programmatically.
repl.tokenize('ls | grep foo')         # => Array of Rubish::Lexer::Token (each
                                       #    with :type and :value) for syntax
                                       #    highlighting; never raises.
repl.try_parse('if true; then')        # => :ok | :incomplete | :error
                                       #    (use to decide PS2 vs. submit).
repl.parse_ast('echo hi')              # => AST root, or nil on parse failure.
repl.complete_at(line: 'gi', point: 2) # => Array of completion candidates at
                                       #    the cursor.
repl.prompt_segments                   # => Array of styled-text segments
                                       #    {text:, fg:, bg:, bold:, italic:,
                                       #     underline:, inverse:}, ANSI codes
                                       #    already parsed.
repl.right_prompt_segments             # => same shape for the right prompt,
                                       #    or nil if unset.
```

### Custom I/O backend

The default `Rubish::Frontend::Tty` wraps Reline + stdin/stdout. Hosts that own their own line editor can subclass `Rubish::Frontend::Base` and pass an instance into the REPL:

```ruby
class MyFrontend < Rubish::Frontend::Base
  def read_line(prompt:, rprompt: nil)
    # ...feed input from your own UI here
  end
end

Rubish::REPL.new(frontend: MyFrontend.new).run
```

### Child-process pre-exec hook

To run setup code in every forked child between `fork()` and `exec()` (e.g. to attach a per-command controlling tty so the line discipline can deliver `Ctrl-C` to the child):

```ruby
Rubish::Command.child_pre_exec_hook = -> {
  Process.setsid
  # ...ioctls, signal handlers, etc.
}
```

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
