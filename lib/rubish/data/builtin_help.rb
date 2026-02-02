# frozen_string_literal: true

module Rubish
  module Builtins
    BUILTIN_HELP = {
      'cd' => {
        synopsis: 'cd [-L|-P] [dir]',
        description: 'Change the current directory to dir. If dir is not specified, change to $HOME.',
        options: {
          '-L' => 'follow symbolic links (default)',
          '-P' => 'use physical directory structure'
        }
      },
      'exit' => {
        synopsis: 'exit [n]',
        description: 'Exit the shell with a status of n. If n is omitted, exit status is that of the last command executed.'
      },
      'logout' => {
        synopsis: 'logout [n]',
        description: 'Exit a login shell with a status of n. If n is omitted, exit status is that of the last command executed. Prints a warning if not in a login shell.'
      },
      'jobs' => {
        synopsis: 'jobs [-l|-p] [jobspec ...]',
        description: 'List active jobs.',
        options: {
          '-l' => 'list process IDs in addition to normal info',
          '-p' => 'list process IDs only'
        }
      },
      'fg' => {
        synopsis: 'fg [job_spec]',
        description: 'Move job to the foreground. If job_spec is not present, the most recent job is used.'
      },
      'bg' => {
        synopsis: 'bg [job_spec ...]',
        description: 'Move jobs to the background. If job_spec is not present, the most recent job is used.'
      },
      'bindkey' => {
        synopsis: 'bindkey [-l|-L] [-M keymap] [-e|-v|-a] [-r key] [-s key string] [key [widget]]',
        description: 'Manage key bindings for the line editor. Display, add, or remove key bindings.',
        options: {
          '-l' => 'list available keymaps',
          '-L' => 'output bindings in a form suitable for re-input',
          '-M keymap' => 'select keymap to operate on',
          '-e' => 'select emacs keymap',
          '-v' => 'select viins (vi insert mode) keymap',
          '-a' => 'select vicmd (vi command mode) keymap',
          '-r key' => 'remove binding for key',
          '-s key string' => 'bind key to a macro string'
        }
      },
      'export' => {
        synopsis: 'export [-n] [name[=value] ...]',
        description: 'Set export attribute for shell variables. Exported variables are passed to child processes.',
        options: {
          '-n' => 'remove the export property from each name',
          '-p' => 'display all exported variables'
        }
      },
      'pwd' => {
        synopsis: 'pwd [-L|-P]',
        description: 'Print the current working directory.',
        options: {
          '-L' => 'print logical path (default)',
          '-P' => 'print physical path (resolve symlinks)'
        }
      },
      'history' => {
        synopsis: 'history [-c] [-d offset] [n]',
        description: 'Display or manipulate the history list.',
        options: {
          '-c' => 'clear the history list',
          '-d offset' => 'delete the history entry at offset',
          'n' => 'list only the last n entries'
        }
      },
      'autoload' => {
        synopsis: 'autoload [-UXktz] [+X] [name ...]',
        description: 'Mark functions for autoloading from FPATH. The function definition is loaded from a file in FPATH when first called.',
        options: {
          '-U' => 'suppress alias expansion during function loading',
          '-z' => 'use zsh-style autoloading (file contains function body, default)',
          '-k' => 'use ksh-style autoloading (file contains full function definition)',
          '-t' => 'turn on execution tracing for the function',
          '-X' => 'immediately load the function definition',
          '+X' => 'load function immediately without executing'
        }
      },
      'alias' => {
        synopsis: 'alias [name[=value] ...]',
        description: 'Define or display aliases. Without arguments, print all aliases. With arguments, define aliases.'
      },
      'unalias' => {
        synopsis: 'unalias [-a] name [name ...]',
        description: 'Remove each name from the list of defined aliases.',
        options: {
          '-a' => 'remove all alias definitions'
        }
      },
      'source' => {
        synopsis: 'source filename [arguments]',
        description: 'Read and execute commands from filename in the current shell environment.'
      },
      '.' => {
        synopsis: '. filename [arguments]',
        description: 'Read and execute commands from filename in the current shell environment. Same as source.'
      },
      'shift' => {
        synopsis: 'shift [n]',
        description: 'Shift positional parameters to the left by n (default 1).'
      },
      'set' => {
        synopsis: 'set [--] [arg ...]',
        description: 'Set positional parameters, or display shell variables. With -- args, set $1, $2, etc.'
      },
      'return' => {
        synopsis: 'return [n]',
        description: 'Return from a shell function with return value n. If n is omitted, return status is that of the last command.'
      },
      'read' => {
        synopsis: 'read [-a array] [-d delim] [-e] [-i text] [-n nchars] [-N nchars] [-p prompt] [-r] [-s] [-t timeout] [-u fd] [name ...]',
        description: 'Read a line from standard input and split into fields. If no names are supplied, the line is stored in REPLY.',
        options: {
          '-a array' => 'store words in an indexed array (simulated via env vars: ARRAY_0, ARRAY_1, etc.)',
          '-d delim' => 'continue reading until first character of delim is read (instead of newline)',
          '-e' => 'use Readline for input (enables editing, history)',
          '-i text' => 'use text as initial text for Readline (requires -e)',
          '-n nchars' => 'return after reading nchars characters (or delimiter)',
          '-N nchars' => 'return after reading exactly nchars characters (ignores delimiter)',
          '-p prompt' => 'display prompt on stderr before reading',
          '-r' => 'raw mode: do not allow backslash escapes',
          '-s' => 'silent mode: do not echo input (for passwords)',
          '-t timeout' => 'time out and return failure after timeout seconds',
          '-u fd' => 'read from file descriptor fd instead of stdin'
        }
      },
      'echo' => {
        synopsis: 'echo [-n] [-e] [arg ...]',
        description: 'Write arguments to standard output.',
        options: {
          '-n' => 'do not append a newline',
          '-e' => 'enable interpretation of backslash escapes'
        }
      },
      'test' => {
        synopsis: 'test expr',
        description: 'Evaluate conditional expression and return 0 (true) or 1 (false).',
        options: {
          '-b file' => 'true if file is a block special device',
          '-c file' => 'true if file is a character special device',
          '-d file' => 'true if file is a directory',
          '-e file' => 'true if file exists',
          '-f file' => 'true if file is a regular file',
          '-g file' => 'true if file has setgid bit set',
          '-h file' => 'true if file is a symbolic link',
          '-k file' => 'true if file has sticky bit set',
          '-L file' => 'true if file is a symbolic link',
          '-N file' => 'true if file modified since last read',
          '-O file' => 'true if file is owned by effective user ID',
          '-G file' => 'true if file is owned by effective group ID',
          '-p file' => 'true if file is a named pipe (FIFO)',
          '-r file' => 'true if file is readable',
          '-s file' => 'true if file has size greater than zero',
          '-S file' => 'true if file is a socket',
          '-t fd' => 'true if file descriptor is open and refers to a terminal',
          '-u file' => 'true if file has setuid bit set',
          '-w file' => 'true if file is writable',
          '-x file' => 'true if file is executable',
          '-z string' => 'true if string length is zero',
          '-n string' => 'true if string length is non-zero',
          '-v varname' => 'true if shell variable varname is set',
          '-R varname' => 'true if shell variable varname is a nameref',
          's1 = s2' => 'true if strings are equal',
          's1 != s2' => 'true if strings are not equal',
          's1 < s2' => 'true if s1 sorts before s2 lexicographically',
          's1 > s2' => 'true if s1 sorts after s2 lexicographically',
          'n1 -eq n2' => 'true if integers are equal',
          'n1 -ne n2' => 'true if integers are not equal',
          'n1 -lt n2' => 'true if n1 < n2',
          'n1 -le n2' => 'true if n1 <= n2',
          'n1 -gt n2' => 'true if n1 > n2',
          'n1 -ge n2' => 'true if n1 >= n2',
          'f1 -nt f2' => 'true if file f1 is newer than f2',
          'f1 -ot f2' => 'true if file f1 is older than f2',
          'f1 -ef f2' => 'true if f1 and f2 refer to same device and inode',
          'e1 -a e2' => 'true if both e1 and e2 are true',
          'e1 -o e2' => 'true if either e1 or e2 is true',
          '! expr' => 'true if expr is false'
        }
      },
      '[' => {
        synopsis: '[ expr ]',
        description: 'Evaluate conditional expression. Same as test, but requires closing ].'
      },
      'break' => {
        synopsis: 'break [n]',
        description: 'Exit from within a for, while, or until loop. If n is specified, break n levels.'
      },
      'continue' => {
        synopsis: 'continue [n]',
        description: 'Resume the next iteration of the enclosing for, while, or until loop.'
      },
      'pushd' => {
        synopsis: 'pushd [-n] [dir | +N | -N]',
        description: 'Save current directory on stack and change to dir.',
        options: {
          '-n' => 'suppress directory change, only manipulate stack',
          '+N' => 'rotate stack, bringing Nth directory to top',
          '-N' => 'rotate stack, bringing Nth directory from bottom to top'
        }
      },
      'popd' => {
        synopsis: 'popd [-n] [+N | -N]',
        description: 'Remove entries from the directory stack.',
        options: {
          '-n' => 'suppress directory change, only manipulate stack',
          '+N' => 'remove Nth entry from top of stack',
          '-N' => 'remove Nth entry from bottom of stack'
        }
      },
      'dirs' => {
        synopsis: 'dirs [-c] [-l] [-p] [-v]',
        description: 'Display the directory stack.',
        options: {
          '-c' => 'clear the directory stack',
          '-l' => 'use full pathnames (no ~ substitution)',
          '-p' => 'print one entry per line',
          '-v' => 'print with index numbers'
        }
      },
      'trap' => {
        synopsis: 'trap [-lp] [[arg] signal_spec ...]',
        description: 'Set or display signal handlers.',
        options: {
          '-l' => 'list signal names and numbers',
          '-p' => 'display current trap settings'
        }
      },
      'getopts' => {
        synopsis: 'getopts optstring name [args]',
        description: 'Parse positional parameters as options. Sets OPTIND and OPTARG.'
      },
      'local' => {
        synopsis: 'local [-n] [name[=value] ...]',
        description: 'Create local variables within a function. Only valid inside a function.',
        options: {
          '-n' => 'make each name a nameref (reference to another variable)'
        }
      },
      'unset' => {
        synopsis: 'unset [-v] [-f] [name ...]',
        description: 'Unset values and attributes of variables and functions.',
        options: {
          '-v' => 'unset variables (default)',
          '-f' => 'unset functions'
        }
      },
      'readonly' => {
        synopsis: 'readonly [-p] [name[=value] ...]',
        description: 'Mark variables as read-only.',
        options: {
          '-p' => 'display all readonly variables'
        }
      },
      'declare' => {
        synopsis: 'declare [-aAfFgilnprtux] [-p] [name[=value] ...]',
        description: 'Declare variables and give them attributes.',
        options: {
          '-a' => 'indexed array',
          '-A' => 'associative array',
          '-i' => 'integer attribute',
          '-l' => 'convert value to lowercase',
          '-u' => 'convert value to uppercase',
          '-r' => 'make readonly',
          '-x' => 'export to environment',
          '-p' => 'display attributes and values'
        }
      },
      'typeset' => {
        synopsis: 'typeset [-aAfFgilnprtux] [-p] [name[=value] ...]',
        description: 'Declare variables and give them attributes. Same as declare.'
      },
      'let' => {
        synopsis: 'let arg [arg ...]',
        description: 'Evaluate arithmetic expressions. Each arg is an arithmetic expression.'
      },
      'printf' => {
        synopsis: 'printf [-v var] format [arguments]',
        description: 'Write formatted output. Format specifiers: %s (string), %d (integer), %f (float), %q (shell-quoted), %(fmt)T (time), etc.',
        options: {
          '-v var' => 'assign the output to shell variable var instead of printing to stdout',
          '%q' => 'output the argument as a shell-quoted string, safe for reuse as input',
          '%(fmt)T' => 'output date/time using strftime format fmt; argument is epoch seconds (-1=now, -2=shell start)',
          '%*s' => 'dynamic width from argument (negative width means left-align)',
          '%.*s' => 'dynamic precision from argument',
          '%*.*s' => 'both width and precision from arguments'
        }
      },
      'type' => {
        synopsis: 'type [-t|-p|-a] name [name ...]',
        description: 'Display information about command type.',
        options: {
          '-t' => 'print single word: alias, keyword, function, builtin, or file',
          '-p' => 'print disk file path',
          '-a' => 'print all locations'
        }
      },
      'which' => {
        synopsis: 'which [-a] name [name ...]',
        description: 'Locate a command in PATH.',
        options: {
          '-a' => 'print all matching pathnames'
        }
      },
      'true' => {
        synopsis: 'true',
        description: 'Return a successful result (exit status 0).'
      },
      'false' => {
        synopsis: 'false',
        description: 'Return an unsuccessful result (exit status 1).'
      },
      ':' => {
        synopsis: ':',
        description: 'Null command. Does nothing, returns success.'
      },
      'eval' => {
        synopsis: 'eval [arg ...]',
        description: 'Concatenate arguments and execute as a shell command.'
      },
      'command' => {
        synopsis: 'command [-pVv] command [arg ...]',
        description: 'Execute command bypassing shell functions.',
        options: {
          '-p' => 'use default PATH for command search',
          '-v' => 'print command description',
          '-V' => 'print verbose command description'
        }
      },
      'builtin' => {
        synopsis: 'builtin shell-builtin [arguments]',
        description: 'Execute a shell builtin, bypassing functions and aliases.'
      },
      'wait' => {
        synopsis: 'wait [-fn] [-p VARNAME] [id ...]',
        description: 'Wait for job completion and return exit status.',
        options: {
          '-f' => 'wait for job to terminate, not just change state',
          '-n' => 'wait for any single job to complete',
          '-p VARNAME' => 'store PID of exited process in VARNAME'
        }
      },
      'kill' => {
        synopsis: 'kill [-s sigspec | -n signum | -sigspec] pid | jobspec ...',
        description: 'Send a signal to a job or process.',
        options: {
          '-l' => 'list signal names',
          '-s sigspec' => 'specify signal by name',
          '-n signum' => 'specify signal by number'
        }
      },
      'umask' => {
        synopsis: 'umask [-p] [-S] [mode]',
        description: 'Display or set file mode creation mask.',
        options: {
          '-p' => 'output in form that may be reused as input',
          '-S' => 'use symbolic output (u=rwx,g=rx,o=rx)'
        }
      },
      'exec' => {
        synopsis: 'exec [-cl] [-a name] [command [arguments ...]]',
        description: 'Replace the shell with command. With no command, redirections affect current shell.',
        options: {
          '-c' => 'execute with empty environment',
          '-l' => 'place dash in argv[0] (login shell)',
          '-a name' => 'set argv[0] to name'
        }
      },
      'times' => {
        synopsis: 'times',
        description: 'Print accumulated user and system times for the shell and its children.'
      },
      'hash' => {
        synopsis: 'hash [-lr] [-p filename] [-dt] [name ...]',
        description: 'Remember or report command locations. With -d, manage named directories (zsh-style).',
        options: {
          '-r' => 'forget all remembered locations',
          '-l' => 'display in reusable format',
          '-p filename' => 'use filename as location for name',
          '-d' => 'named directories: hash -d name=path (define), hash -d name (show), hash -d (list)',
          '-t' => 'print location for name'
        }
      },
      'disown' => {
        synopsis: 'disown [-h] [-ar] [jobspec ...]',
        description: 'Remove jobs from the job table.',
        options: {
          '-h' => 'mark jobs so they do not receive SIGHUP',
          '-a' => 'remove all jobs',
          '-r' => 'remove only running jobs'
        }
      },
      'ulimit' => {
        synopsis: 'ulimit [-SHa] [-bcdefiklmnpqrstuvxT] [limit]',
        description: 'Control process resource limits.',
        options: {
          '-S' => 'use soft limit',
          '-H' => 'use hard limit',
          '-a' => 'all current limits are reported',
          '-c' => 'core file size',
          '-d' => 'data segment size',
          '-f' => 'file size',
          '-l' => 'locked memory size',
          '-m' => 'resident set size',
          '-n' => 'open file descriptors',
          '-s' => 'stack size',
          '-t' => 'CPU time',
          '-u' => 'user processes',
          '-v' => 'virtual memory'
        }
      },
      'suspend' => {
        synopsis: 'suspend [-f]',
        description: 'Suspend shell execution.',
        options: {
          '-f' => 'force suspend even if this is a login shell'
        }
      },
      'shopt' => {
        synopsis: 'shopt [-pqsu] [-o] [optname ...]',
        description: 'Set and unset shell options.',
        options: {
          '-s' => 'enable (set) each optname',
          '-u' => 'disable (unset) each optname',
          '-p' => 'display in reusable format',
          '-q' => 'quiet mode, return status indicates if set',
          '-o' => 'restrict optnames to those defined for set -o'
        }
      },
      'enable' => {
        synopsis: 'enable [-a] [-dnps] [-f filename] [name ...]',
        description: 'Enable and disable shell builtins.',
        options: {
          '-a' => 'print all builtins with enabled/disabled status',
          '-n' => 'disable builtin names',
          '-p' => 'print enabled builtins',
          '-s' => 'print only special builtins'
        }
      },
      'caller' => {
        synopsis: 'caller [expr]',
        description: 'Return the context of the current subroutine call. With expr, return the nth entry from the call stack.'
      },
      'complete' => {
        synopsis: 'complete [-abcdefgjksuv] [-pr] [-DEI] [-o comp-option] [-A action] [-G globpat] [-W wordlist] [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [name ...]',
        description: 'Specify how arguments are to be completed.',
        options: {
          '-p' => 'print completion specifications',
          '-r' => 'remove completion specifications',
          '-f' => 'complete with filenames',
          '-d' => 'complete with directories',
          '-b' => 'complete with builtins',
          '-a' => 'complete with aliases',
          '-v' => 'complete with variables',
          '-W wordlist' => 'split wordlist and complete with results',
          '-F function' => 'call function for completions'
        }
      },
      'compgen' => {
        synopsis: 'compgen [-abcdefgjksuv] [-o option] [-A action] [-G globpat] [-W wordlist] [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [word]',
        description: 'Generate possible completions matching word.',
        options: {
          '-a' => 'aliases',
          '-b' => 'builtins',
          '-c' => 'commands',
          '-d' => 'directories',
          '-e' => 'exported variables',
          '-f' => 'filenames',
          '-g' => 'groups',
          '-j' => 'jobs',
          '-k' => 'shell reserved words',
          '-s' => 'services',
          '-u' => 'users',
          '-v' => 'variables',
          '-A action' => 'use action (alias, arrayvar, binding, builtin, command, directory, disabled, enabled, export, file, function, group, helptopic, hostname, job, keyword, running, service, setopt, shopt, signal, stopped, user, variable)',
          '-C command' => 'execute command and use output as completions',
          '-F function' => 'call function to generate completions',
          '-G globpat' => 'expand glob pattern for completions',
          '-W wordlist' => 'split wordlist and use as completions',
          '-X filterpat' => 'remove completions matching pattern',
          '-P prefix' => 'add prefix to each completion',
          '-S suffix' => 'add suffix to each completion'
        }
      },
      'compinit' => {
        synopsis: 'compinit [-u] [-d dumpfile] [-C]',
        description: 'Initialize the zsh completion system. Sets up default completions and enables programmable completion.',
        options: {
          '-u' => 'skip security check for insecure directories',
          '-d dumpfile' => 'specify dump file for caching completions',
          '-C' => 'skip checking for new completion functions'
        }
      },
      'compdef' => {
        synopsis: 'compdef [-and] function command...',
        description: 'Define zsh-style completion. Associates a completion function with one or more commands.',
        options: {
          '-n' => 'do not override existing completion',
          '-d' => 'delete completion for specified commands',
          '-a' => 'autoload the completion function',
          '-p pattern' => 'use pattern-based completion matching'
        }
      },
      'compopt' => {
        synopsis: 'compopt [-o option] [-DE] [+o option] [name ...]',
        description: 'Modify completion options for the currently executing completion, or for named commands.',
        options: {
          '-o option' => 'enable completion option',
          '+o option' => 'disable completion option',
          '-D' => 'apply to default completion',
          '-E' => 'apply to empty command completion',
          'bashdefault' => 'perform bash default completions if no matches',
          'default' => 'use readline default filename completion',
          'dirnames' => 'perform directory name completion',
          'filenames' => 'tell readline completions are filenames',
          'noquote' => 'do not quote completions',
          'nosort' => 'do not sort completions alphabetically',
          'nospace' => 'do not append space after completion',
          'plusdirs' => 'add directory names to generated matches'
        }
      },
      'bind' => {
        synopsis: 'bind [-m keymap] [-lpsvPSVX] [-f filename] [-q name] [-u name] [-r keyseq] [-x keyseq:shell-command] [keyseq:readline-function or keyseq:"macro"]',
        description: 'Set or display readline key bindings and variables.',
        options: {
          '-l' => 'list readline function names',
          '-p' => 'print key bindings',
          '-P' => 'print key bindings with descriptions',
          '-s' => 'print macro bindings',
          '-S' => 'print macro bindings with descriptions',
          '-v' => 'print readline variables',
          '-V' => 'print readline variables with descriptions',
          '-X' => 'print shell command bindings',
          '-q name' => 'query which keys invoke named function',
          '-u name' => 'unbind all keys bound to named function',
          '-r keyseq' => 'remove binding for keyseq',
          '-f filename' => 'read bindings from filename',
          '-x keyseq:cmd' => 'bind keyseq to shell command',
          '-m keymap' => 'use keymap for subsequent bindings'
        }
      },
      'help' => {
        synopsis: 'help [-dms] [pattern ...]',
        description: 'Display information about builtin commands.',
        options: {
          '-d' => 'output short description for each topic',
          '-m' => 'display in pseudo-manpage format',
          '-s' => 'output only a short usage synopsis'
        }
      },
      'fc' => {
        synopsis: 'fc [-e ename] [-lnr] [first] [last] or fc -s [pat=rep] [command]',
        description: 'Display or edit and re-execute commands from the history list.',
        options: {
          '-e ename' => 'use ename as the editor (default: $FCEDIT or $EDITOR or vi)',
          '-l' => 'list commands instead of editing',
          '-n' => 'suppress line numbers when listing',
          '-r' => 'reverse the order of the commands',
          '-s' => 're-execute command without invoking editor'
        }
      },
      'mapfile' => {
        synopsis: 'mapfile [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]',
        description: 'Read lines from standard input into an indexed array variable.',
        options: {
          '-d delim' => 'use delim as line delimiter instead of newline',
          '-n count' => 'read at most count lines (0 means all)',
          '-O origin' => 'begin assigning at index origin (default 0)',
          '-s count' => 'skip the first count lines',
          '-t' => 'remove trailing delimiter from each line',
          '-u fd' => 'read from file descriptor fd instead of stdin',
          '-C callback' => 'evaluate callback each time quantum lines are read',
          '-c quantum' => 'specify the number of lines between callback calls (default 5000)'
        }
      },
      'readarray' => {
        synopsis: 'readarray [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]',
        description: 'Read lines from standard input into an indexed array variable. Synonym for mapfile.'
      },
      'basename' => {
        synopsis: 'basename NAME [SUFFIX]',
        description: 'Strip directory and suffix from filenames. Print NAME with any leading directory components removed. If SUFFIX is specified, also remove a trailing SUFFIX.',
        options: {
          '-a, --multiple' => 'support multiple arguments and treat each as a NAME',
          '-s, --suffix=SUFFIX' => 'remove a trailing SUFFIX; implies -a',
          '-z, --zero' => 'end each output line with NUL, not newline'
        }
      },
      'dirname' => {
        synopsis: 'dirname NAME...',
        description: 'Strip last component from file name. Output each NAME with its last non-slash component and trailing slashes removed; if NAME contains no slashes, output "." (meaning the current directory).',
        options: {
          '-z, --zero' => 'end each output line with NUL, not newline'
        }
      },
      'realpath' => {
        synopsis: 'realpath [OPTION]... FILE...',
        description: 'Print the resolved absolute file name. All but the last component must exist.',
        options: {
          '-e, --canonicalize-existing' => 'all components of the path must exist',
          '-m, --canonicalize-missing' => 'no path components need exist or be a directory',
          '-q, --quiet' => 'suppress most error messages',
          '-s, --strip, --no-symlinks' => 'don\'t expand symlinks',
          '-z, --zero' => 'end each output line with NUL, not newline'
        }
      },
      # Bash-completion helper functions
      '_get_comp_words_by_ref' => {
        synopsis: '_get_comp_words_by_ref [-n EXCLUDE] [-c VAR] [-p VAR] [-w VAR] [-i VAR] [cur] [prev] [words] [cword]',
        description: 'Get completion words from COMP_WORDS with optional word-break exclusion. Sets cur, prev, words array, and cword index variables.',
        options: {
          '-n EXCLUDE' => 'characters to exclude from COMP_WORDBREAKS',
          '-c VAR' => 'store current word in VAR (default: cur)',
          '-p VAR' => 'store previous word in VAR (default: prev)',
          '-w VAR' => 'store words array in VAR (default: words)',
          '-i VAR' => 'store cword index in VAR (default: cword)'
        }
      },
      '_init_completion' => {
        synopsis: '_init_completion [-n EXCLUDE] [-s]',
        description: 'Initialize completion with common setup. Calls _get_comp_words_by_ref and optionally splits --option=value.',
        options: {
          '-n EXCLUDE' => 'characters to exclude from COMP_WORDBREAKS',
          '-s' => 'split on = for --option=value (sets prev to option, cur to value)'
        }
      },
      '_filedir' => {
        synopsis: '_filedir [-d] [PATTERN]',
        description: 'Complete filenames and directories. Adds matching files/directories to COMPREPLY.',
        options: {
          '-d' => 'only complete directories',
          'PATTERN' => 'glob pattern to filter files (directories always included)'
        }
      },
      '_have' => {
        synopsis: '_have COMMAND',
        description: 'Check if a command exists in PATH or is a builtin. Returns true if found, false otherwise.'
      },
      '_split_longopt' => {
        synopsis: '_split_longopt',
        description: 'Handle --option=value completion. If cur contains =, splits it: sets prev to option part, cur to value part.'
      },
      '__ltrim_colon_completions' => {
        synopsis: '__ltrim_colon_completions CUR',
        description: 'Remove colon prefix from COMPREPLY entries. Used when cur contains colons (e.g., package:version).'
      },
      '_variables' => {
        synopsis: '_variables',
        description: 'Complete shell variable names. Adds $VAR entries matching cur to COMPREPLY.'
      },
      '_tilde' => {
        synopsis: '_tilde',
        description: 'Complete tilde expressions (~username). Only operates when cur starts with ~.'
      },
      '_quote_readline_by_ref' => {
        synopsis: '_quote_readline_by_ref VARNAME VALUE',
        description: 'Quote special characters in VALUE for readline and store in VARNAME.'
      },
      '_parse_help' => {
        synopsis: '_parse_help COMMAND [HELP_OPTION]',
        description: 'Parse command --help output to extract options. Adds matching options to COMPREPLY.',
        options: {
          'HELP_OPTION' => 'option to get help (default: --help)'
        }
      },
      '_upvars' => {
        synopsis: '_upvars [-v VAR VALUE]... [-a N ARRAY VALUES...]...',
        description: 'Set variables in caller\'s scope.',
        options: {
          '-v VAR VALUE' => 'set scalar variable VAR to VALUE',
          '-a N ARRAY VALUES' => 'set array variable ARRAY to N VALUES'
        }
      },
      '_usergroup' => {
        synopsis: '_usergroup [-u] [-g]',
        description: 'Complete usernames or user:group combinations.',
        options: {
          '-u' => 'complete usernames only',
          '-g' => 'complete groups only'
        }
      },
      'setopt' => {
        synopsis: 'setopt [option ...]',
        description: 'Enable shell options (zsh-style). Option names are case-insensitive and underscores are ignored. Without arguments, lists all enabled options. Prefix option with "no" to disable (e.g., noautocd).'
      },
      'unsetopt' => {
        synopsis: 'unsetopt [option ...]',
        description: 'Disable shell options (zsh-style). Option names are case-insensitive and underscores are ignored. Without arguments, lists all disabled options. Prefix option with "no" to enable (e.g., noautocd enables autocd).'
      },
      '__git_ps1' => {
        synopsis: '__git_ps1 [format]',
        description: 'Print git repository status for use in shell prompts. Compatible with bash git-prompt.sh. Shows branch name, detached HEAD state, and optional status indicators.',
        options: {
          'GIT_PS1_SHOWDIRTYSTATE' => 'show * for unstaged, + for staged changes',
          'GIT_PS1_SHOWSTASHSTATE' => 'show $ if stash is not empty',
          'GIT_PS1_SHOWUNTRACKEDFILES' => 'show % if there are untracked files',
          'GIT_PS1_SHOWUPSTREAM' => 'show < behind, > ahead, = up-to-date, <> diverged'
        }
      },
      'require' => {
        synopsis: 'require name',
        description: 'Load Ruby library using Ruby\'s require method.'
      }
    }.freeze
  end
end
