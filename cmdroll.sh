# shellcheck shell=sh
# shellcheck disable=SC2317,SC2329   # silence code unreachability warnings
# vim: set ft=sh ts=4 sw=4 noet ai tw=79:

# cmdroll: a portable and embeddable shell script micro-framework to create
#          handy command wrappers    <https://github.com/nclsgd/cmdroll>
# Version 1.0.2
# SPDX-License-Identifier: 0BSD
# Copyright (C) 2025-2026 Nicolas Godinho <nicolas@godinho.me>

# cmdroll dedicated constants and runtime checks:
CMDROLL_ARGZERO="${0:?}"
# Handle zsh pure mode where $0 would be the cmdroll file and not the source:
if [ "${ZSH_ARGZERO:-}" ] && [ "$(builtin emulate 2>/dev/null)" = zsh ]; then
	CMDROLL_ARGZERO="$ZSH_ARGZERO"
fi
readonly CMDROLL_ARGZERO

# Write a message on stderr with a context prefix:
say() {
	# shellcheck disable=SC2015   # yes, A && B || C is not if-then-else
	printf>&2 '%s:' "${__CMDROLL_SELF:-${CMDROLL_ARGZERO:-$0}}" &&\
	printf>&2 ' %s' "$@" && printf>&2 '\n' ||:
}

# Terminate shell with a context-prefixed explanation message on stderr:
die() {
	[ "${1+x}" ] || set -- "an error has occurred"
	# shellcheck disable=SC2015   # yes, A && B || C is not if-then-else
	printf>&2 '%s:' "${__CMDROLL_SELF:-${CMDROLL_ARGZERO:-$0}}" &&\
	printf>&2 ' %s' "$@" && printf>&2 '\n' ||:
	exit 1
}

# Trim leading and trailing whitespaces:
# (Note: IFS concatenation is followed when multiple arguments are provided)
trim() {
	set -- "$*" && set -- "${1#"${1%%[![:space:]]*}"}" &&\
	printf '%s' "${1%"${1##*[![:space:]]}"}" || exit 1
}

# Ensure sed is available via PATH resolution:
[ "${CMDROLL_NOSEDCHECK:-}" ] || case "$(command -v sed)" in \
/*);; *) die "cmdroll: \`sed' seems unfound in PATH";; esac

# Quote arguments following POSIX shell escaping rules:
quote() {
	while [ "${1+x}" ]; do
		printf '|%s|' "$1" | sed \
			"s/'/'\\\\''/g; 1s/^|/'/; \$s/|\$/'/;${2+" \$s/\$/ /;"}" || exit 1
		shift
	done
}

# Retrieve from parent script the user working directory (if provided):
: "${CMDROLL_USERWORKDIR:="${PWD:?}"}"
readonly CMDROLL_USERWORKDIR

# Compute path relative to the user working directory (CMDROLL_USERWORKDIR):
rel2uwd() {
	case "$CMDROLL_USERWORKDIR" in /*);; *) die \
		"rel2uwd: CMDROLL_USERWORKDIR is not an absolute path";; esac
	case "$#" in 0) die "rel2uwd: missing path";; 1);; *) die \
		"rel2uwd: too many arguments";; esac
	case "${1:?}" in
		/*) printf '%s' "$1";;
		*)  printf '%s' "$CMDROLL_USERWORKDIR/$1";;
	esac
}

# Retrieve the shell to be used by the parent script:
CMDROLL_SHELL="$(cd "$CMDROLL_USERWORKDIR" &&\
	sed <"$CMDROLL_ARGZERO" 's/^#!//;q')" || die
CMDROLL_SHELL="$(trim "$CMDROLL_SHELL")" || die
case "$CMDROLL_SHELL" in
	'') die "cmdroll: \$0 does not begin with a shebang: $CMDROLL_ARGZERO";;
	[!/]*|*[!/a-zA-Z0-9_:,.\ +-]*)
		die "cmdroll: unexpected shebang read: #!$CMDROLL_SHELL";;
esac

# Shell special features:
CMDROLL_SHELLFEAT=''
# Probe if the shell supports readonly functions with `readonly -f' (Bash):
if [ "$(eval 2>/dev/null \
'_f(){ echo 1;}; readonly>&2 -f _f||:; _f(){ echo 2;}||:; _f||:')" = 1 ]; then
	CMDROLL_SHELLFEAT="$CMDROLL_SHELLFEAT${CMDROLL_SHELLFEAT:+:}readonlyfuncs"
fi
# Probe if the shell does not word-split the same way POSIX sh does (zsh):
# shellcheck disable=SC2086  # word splitting is expected here
case "$(___v="a b"; set -- $___v; echo $#)" in
	2) :;;
	1) CMDROLL_SHELLFEAT="$CMDROLL_SHELLFEAT${CMDROLL_SHELLFEAT:+:}zshnowordsplit";;
	*) die "unexpected result while probing for shell word splitting behavior";;
esac
readonly CMDROLL_SHELLFEAT

# Mark the basic utility functions as readonly if supported:
case ":$CMDROLL_SHELLFEAT:" in *:readonlyfuncs:*)
	# shellcheck disable=SC3045  # `readonly -f' support is validated above
	readonly -f say die trim quote rel2uwd ;;
esac

# If "zshnowordsplit", treat CMDROLL_SHELL as array for auto word-split:
case ":$CMDROLL_SHELLFEAT:" in *:zshnowordsplit:*)
	eval "CMDROLL_SHELL=($CMDROLL_SHELL)";;
esac

# Freeze CMDROLL_SHELL:
readonly CMDROLL_SHELL

__CMDROLL_CMDS='# cmdroll commands defintion table, DO NOT EDIT!'
__CMDROLL_CURSECTION=''
unset ABOUT

# Declaring CMD (commands):
CMD() { _cmdroll_CMD "$@"; }
_cmdroll_CMD() {
	___v=''  # function name behind the command
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-f)  [ "${1+x}" ] || die "CMD: missing function name"
		     [ ! "$___v" ] || die "CMD: option $___o can only be used once"
		     ___v="$1"; shift ;;
		-[f]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "CMD: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "CMD: missing command name"
	: "${___v:="$1"}"
	case "$___v" in
		''|-*|*[!a-zA-Z0-9_.:@+-]*) die "CMD: invalid command name: $1";;
		[!a-zA-Z_]*|*[!a-zA-Z0-9_]*)
			[ "$(eval 2>/dev/null "$___v(){ echo ok;}&& $___v")" = ok ] || die \
				"CMD: accepted command name but illegal function name: $___v"
	esac
	[ "${__CMDROLL_CURSECTION:-}" ] && {
		__CMDROLL_CMDS="$__CMDROLL_CMDS
$__CMDROLL_CURSECTION"
		__CMDROLL_CURSECTION=''
	}
	__CMDROLL_CMDS="$__CMDROLL_CMDS
$___v"  # no leading whitespace here!
	unset ___v
	while [ "${1+x}" ]; do
		case "$1" in
			--) shift; break ;;
			''|-*|*[!a-zA-Z0-9_.:@+-]*) die "CMD: invalid command name: $1";;
		esac
		__CMDROLL_CMDS="$__CMDROLL_CMDS $1"; shift
	done
	if [ "${1+x}" ]; then
		__CMDROLL_CMDS="$__CMDROLL_CMDS
$(trim "$(printf '%s ' "$@")" | sed '/^[[:space:]]*$/d;s/^/\t/')"
	fi
}

# Declaring command sections:
CMDSECTION() { _cmdroll_CMDSECTION "$@"; }
_cmdroll_CMDSECTION() {
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		--)  break ;;
		-?*) die "CMDSECTION: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	__CMDROLL_CURSECTION="$(trim "$(printf '%s ' "$@")" | sed \
		'/^[[:space:]]*$/d;s/^/>/')"
}

# Evaluate all the command definitions in the parent script:
eval "$(cd "$CMDROLL_USERWORKDIR" && sed -n <"$CMDROLL_ARGZERO" \
's/^__CMDROLL__//;t a;b;:a /^[[:blank:]]*$/bb;/^[[:blank:]][[:blank:]]*#/bb;b;:b {n;p;bb;}')"

# Invoke another command from the cmdroll script (potentially wrapped by a
# function or command provided with the `-w' option):
invoke() {
	___w=''  # wrapper function or command
	___x=''  # whether to pass -x again
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-w)  [ "${1+x}" ] || die "invoke: missing wrapper function or command"
		     [ ! "$___w" ] || die "invoke: option $___o can only be used once"
		     ___w="$1"; shift ;;
		-x)  ___x=x ;;
		-[w]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		-[x]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "invoke: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "invoke: missing command"
	if [ "$___w" ]; then
		# shellcheck disable=SC2016  # no expansion between single quotes
		# shellcheck disable=SC2086  # word splitting is expected here
		set -- $___w /bin/sh -c 'cd "$0" && exec "$@"' \
			"${CMDROLL_USERWORKDIR:?}" \
			${CMDROLL_SHELL:?} "${CMDROLL_ARGZERO:?}" ${CMDROLL_OPTS?} \
			${___x:+-x} -- "$@"
		unset ___w ___x
		"$@"
	else
		# shellcheck disable=SC2086  # word splitting is expected here
		set -- ${CMDROLL_SHELL:?} "${CMDROLL_ARGZERO:?}" ${CMDROLL_OPTS?} \
			${___x:+-x} -- "$@"
		unset ___w ___x
		( cd "${CMDROLL_USERWORKDIR:?}" && exec "$@" )
	fi
}

# Chain cmdroll commands:
chain() {
	# NB: these "fake" local vars must not collide with those of invoke
	___d=''  # the delimiter value
	___D=''  # is the delimiter defined?
	___v=''  # verbosity
	___X=''  # xtrace on invoked commands
	___C='die'  # function to call on invoke returning an error
	while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
		-d)  [ "${1+x}" ] || die "misused: missing delimiter"
		     [ ! "$___D" ] || die "misused: option $___o can only be used once"
		     ___d="$1"; ___D=x; shift ;;
		-v)  ___v=x;;
		-x)  ___X=x; ___v=x;;
		-h) printf '%s\n' "\
usage: $CMDROLL_ARGZERO chain [-vxC]          COMMAND [COMMAND...]
       $CMDROLL_ARGZERO chain [-vxC] -d DELIM COMMAND [ARGS...] [DELIM COMMAND [ARGS...]]...
       $CMDROLL_ARGZERO chain -h

invoke commands in sequence

options:  -v        be verbose and print the invoked commands
          -d DELIM  specify a delimiter value to allow arguments on chained
                    commands  [tip: commas \`,' usually make good delimiters]
          -x        enable xtrace on the invoked commands  [implies -v]
          -C        continue: do not stop sequence upon failed commands
          -h        display this help and exit"; exit 0;;
		-C) ___C='say';;
		-[d]?*) set -- "${___o%"${___o#??}"}" "${___o#??}" "$@" ;;
		-[vxCh]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
		--)  break ;;
		-?*) die "misused: unknown option ${___o%"${___o#??}"}" ;;
		*)   set -- "$___o" "$@"; break ;;
	esac; done; unset ___o
	[ "${1+x}" ] || die "no commands given"
	# Without command delimiter defined:
	if [ ! "$___D" ]; then
		while [ "${1+x}" ]; do
			[ "$___v" ] && say "invoking command: $1"
			invoke ${___X:+-x} -- "$1" || "$___C" "command returned $?: $1"
			shift
		done
		unset ___d ___D ___v ___X ___C; return 0
	fi
	# With command delimiter defined:
	___i=1; ___j=1; ___k=''; ___l=''
	while [ "$___j" -le "$#" ]; do
		eval "___k=\"\${$___j}\""
		if [ "$___k" = "$___d" ]; then
			if [ "$___i" != "$___j" ]; then
				___l="$(
					set -- "$___i" "$((___j-1))"
					while [ "$1" -le "$2" ]; do
						# shellcheck disable=SC2016
						printf ' "${%d}"' "$1"
						set -- "$(($1+1))" "$2"
					done)"
				[ "$___v" ] && eval "say \"invoking command:\"$___l"
				eval "invoke ${___X:+-x} -- $___l || $___C \"command returned \$?:\" $___l"
			fi
			___i="$((___j+1))"
		fi
		___j="$((___j+1))"
	done
	if [ "$___i" != "$___j" ]; then
		___l="$(
			set -- "$___i" "$((___j-1))"
			while [ "$1" -le "$2" ]; do
				# shellcheck disable=SC2016
				printf ' "${%d}"' "$1"
				set -- "$(($1+1))" "$2"
			done)"
		[ "$___v" ] && eval "say \"invoking command:\"$___l"
		eval "invoke ${___X:+-x} -- $___l || $___C \"command returned \$?:\" $___l"
	fi
	unset ___d ___D ___v ___X ___C ___i ___j ___k ___l
}

# Help and usage description listing all the available cmdroll commands:
cmdroll_usage() {
	printf '%s\n' "\
usage: $CMDROLL_ARGZERO [-x] COMMAND [ARGS...]
       $CMDROLL_ARGZERO -h|-c
options:   -h   display this help and exit
           -x   enable xtrace during command invocation
           -c   generate a Bash completion script and exit
" || return 1
	[ "$(printf '%s\n' "$__CMDROLL_CMDS" | sed '/^[#>[:blank:]]/d; /^$/d')" ] || {
		printf '%s\n' "no commands defined or missing \`__CMDROLL__' marker line"
		return
	}
	printf '%s\n' "commands:"
	printf '%s\n' "$__CMDROLL_CMDS" | sed -n '/^#/d; /^$/d;
/^>/ { s/^>/\n -- /p; :H { n; s/^>/ -- /p; t H; } }
/^\t/ { s/^\t/                        /p; b; }
s/^[^ ]* //;
s/ /, /g; s/^/  /; $p; N;
/\n\t/!{ P; D; }
s/\n/                        \n/;
s/^\(.....................\)    *\n\t/\1   /;
/^.....................   /!s/ *\n\t/\n                        /;
p;'
	ABOUT="$(trim "${ABOUT:-}")"
	if [ "$ABOUT" ]; then printf '\n%s\n' "$ABOUT"; fi
}

cmdroll_bash_completion_script() {
	if [ -t 1 ] && [ ! "${CMDROLL_STDOUTISATTY:-}" ]; then
		say "cmdroll: unexpected: stdout is a tty"
		die "\
cmdroll: the completion script must be evaluated by the shell, try running:
    . <($CMDROLL_ARGZERO -c)"
	fi
	# shellcheck disable=SC2016
	printf '%s\n' '__cmdroll_scripts_completion() {
	local _script="${COMP_WORDS[0]}"
	[[ -f "$_script" &&\
	   -x "$_script" &&\
	   "$_script" =~ .+/.+ &&\
	   -n "$(sed "/^#!/p;q" <"$_script")" &&\
	   -n "$(sed -n <"$_script" "s/^__CMDROLL__//; t a; b;
:a s/^[[:blank:]]*\$//; t b; s/^[[:blank:]][[:blank:]]*#//; t b; b; :b =; q")" ]] || return 1
	case "${COMP_WORDS[COMP_CWORD]}" in
		/*|./*|../*)
			mapfile -t COMPREPLY < <(compgen -f -- "${COMP_WORDS[COMP_CWORD]}");;
		*)
			local __cmds
			__cmds="$(CMDROLL_COMPLETION=bash "$_script" -\$)"
			[[ "$__cmds" ]] && mapfile -t COMPREPLY < <(compgen -W "-h $__cmds" \
				-- "${COMP_WORDS[COMP_CWORD]}")
	esac
}
_cmdroll_complete() {
	local _c; for _c; do case "$_c" in
		""|*[!a-zA-Z0-9_.+-]*)
			echo >&2 "_cmdroll_complete: skipping unsupported script basename: $_c" ||:
			;;
		*)
			__cmdroll_completions+=("$_c")
			complete -F __cmdroll_scripts_completion -- "$_c" "./$_c"
			;;
	esac; done
}
_cmdroll_remove_completions() {
	local _c; for _c in "${__cmdroll_completions[@]}"; do
		complete -r -- "$_c" "./$_c"
	done
	unset __cmdroll_completions
}'
	printf '%s\n' "_cmdroll_complete $(quote "${CMDROLL_ARGZERO##*/}")"
}

# Mark our functions as readonly if the shell supports it:
case ":$CMDROLL_SHELLFEAT:" in *:readonlyfuncs:*)
	# shellcheck disable=SC3045  # `readonly -f' support is validated above
	readonly -f invoke chain cmdroll_usage
esac

# Inject the chain command definition:
[ "${CMDROLL_NOCHAIN:-}" ] || {
: "${CMDROLL_CHAINALIAS=ch}"  # default alias to the chain command
case " ${CMDROLL_CHAINALIAS:-}" in *[!" "a-zA-Z0-9_.:@+-]*|*" "-*) \
die "cmdroll: invalid chain command alias definition: $CMDROLL_CHAINALIAS";; esac
[ "$(printf '%s\n' "$__CMDROLL_CMDS" | sed '/^[#>[:blank:]]/d; /^$/d')" ] &&\
	__CMDROLL_CMDS="$(printf '%s\n' "$__CMDROLL_CMDS" | sed -n "
/^>/ { i\\
chain chain ${CMDROLL_CHAINALIAS:-}\\
	invoke commands in sequence  (\`chain -h' for more info)
b cont; }
\$ { a\\
chain chain ${CMDROLL_CHAINALIAS:-}\\
	invoke commands in sequence  (\`chain -h' for more info)
b cont; }
p; b; :cont { p; n; b cont; }")"
}

readonly __CMDROLL_CMDS
unset __CMDROLL_CURSECTION
unset -f CMD _cmdroll_CMD CMDSECTION _cmdroll_CMDSECTION

# Check there is no duplicate commands
# shellcheck disable=SC2016
___v="$(printf '\n%s\n' "$__CMDROLL_CMDS" | sed -n '
:B $bE; s/\n[#>[:blank:]].*//; tB; s/\n[^ ]*  *\(.*\)/\1 /; N; bB;
:E      s/\n[#>[:blank:]].*//;     s/\n[^ ]*  *\(.*\)/\1 /;
s/  */ /g; s/ *$//; p;')" || die
while [ "${___v#* }" != "${___v%% *}" ]; do
	case " ${___v#* } " in *" ${___v%% *} "*)
		die "cmdroll: duplicate definition for command or alias: ${___v%% *}";;
	esac
	___v="${___v#* }"
done
unset ___v

# Check that all the commands have their expected functions:
[ "${CMDROLL_NOCMDFUNCCHECK:-}" ] || for ___v in \
$(printf '%s\n' "$__CMDROLL_CMDS" | sed '/^[#>[:blank:]]/d; /^$/d; s/ .*//;'); do
	[ "$(PATH='' command -v "$___v" 2>/dev/null ||:)" ] || die \
		"cmdroll: missing command function: $___v"
done
unset ___v

___x=''  # xtrace option
while [ "${1+x}" ]; do ___o="$1"; shift; case "$___o" in
	-x) ___x=x ;;
	-h) cmdroll_usage; exit "$?" ;;
	-c) cmdroll_bash_completion_script; exit "$?" ;;
	-\$) printf '%s\n' "$__CMDROLL_CMDS" | sed '/^[#>[:blank:]]/d; /^$/d;
s/^[^ ]*  *//; s/ .*//;'; exit "$?";;
#	-\&) printf '%s\n' "$__CMDROLL_CMDS" | sed '/^[#>[:blank:]]/d; /^$/d;
#s/^[^ ]*  *//; s/  */ /g; s/ *$//;'; exit "$?";;
	-[xhc\$]?*) set -- "${___o%"${___o#??}"}" "-${___o#??}" "$@" ;;
	--)  break ;;
	-?*) die "cmdroll: unknown option ${___o%"${___o#??}"}" ;;
	*)   set -- "$___o" "$@"; break ;;
esac; done; unset ___o
[ "${1+x}" ] || { cmdroll_usage>&2 ||:; exit 1; }

CMDROLL_OPTS="${___x:+-x}"

# If "zshnowordsplit", treat CMDROLL_OPTS as array for auto word-split:
case ":$CMDROLL_SHELLFEAT:" in *:zshnowordsplit:*)
	eval "CMDROLL_OPTS=($CMDROLL_OPTS)";;
esac

# Freeze CMDROLL_OPTS:
readonly CMDROLL_OPTS

___c="$(
	case "$1" in
		''|-*|*[!a-zA-Z0-9_.:@+-]*) die "invalid command name: $1";;
		*.*) ___v="$(printf '%s' "$1" | sed 's/\./\\./g')" || die;;
		*) ___v="$1";;
	esac
	# shellcheck disable=SC2016
	printf '%s\n' "$__CMDROLL_CMDS" | sed -n '/^[#>[:blank:]]/d; /^$/d;
s/$/ /; / '"$___v"' /!b; s/^\([^ ]*  *[^ ]*\).*/\1/; ${p; q;}; N;
s/\n\t/ /p; t hlp; s/\n.*//; p; q; :hlp n; s/^\t//p; t hlp; q' || die
)" || exit 1
[ "$___c" ] || die "unknown command: $1"
CMDFUNC="${___c%% *}"; CMD="${___c#"$CMDFUNC "}"; CMD="${CMD%%" "*}";
CMDHELP="${___c#"$CMDFUNC $CMD "}"
unset ___c; shift
# shellcheck disable=SC2034  # CMDHELP is unused here but left for users
readonly CMD CMDFUNC CMDHELP

# Append the command name to the self contaxtual value for say/die:
__CMDROLL_SELF="$CMDROLL_ARGZERO $CMD"

# That's it, handle the xtrace option (if asked), run the command and exit:
if [ "$___x" ]; then unset ___x; set -x; else unset ___x; fi
"$CMDFUNC" "$@"
exit "$?"
