#!/bin/sh
set -eu

REPO=${LUNAR_REPO:-Glazastyy/Lunar}
REF=${LUNAR_REF:-}
PREFIX=${LUNAR_HOME:-$HOME/.lunar}
BIN_DIR=${LUNAR_BIN_DIR:-$HOME/.local/bin}

LUA_VERSION=5.4.9
LUA_SHA256=2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6
LUASOCKET_VERSION=3.1.0
LUASOCKET_SHA256=bf033aeb9e62bcaa8d007df68c119c966418e8c9ef7e4f2d7e96bddeca9cca6e

FROM=
LUA_BIN=
BUILD_LUA=0
WANT_SOCKET=1
MODIFY_PATH=1
ACTION=install
QUIET=0
STYLE=0
SPINNER_PID=

spinner_stop() {
	[ -n "$SPINNER_PID" ] || return 0
	kill "$SPINNER_PID" 2>/dev/null || true
	wait "$SPINNER_PID" 2>/dev/null || true
	SPINNER_PID=
	printf '\r\033[2K' >&2
}

spinner_start() {
	[ "$STYLE" = 1 ] && [ "$QUIET" = 0 ] && [ "${LUNAR_ANIMATIONS:-1}" != 0 ] || return 0
	spinner_stop
	(
		trap 'exit 0' TERM INT HUP
		while :; do
			for frame in '·    ' ' ·   ' '  ●  ' '   · ' '    ·' '   · ' '  ●  ' ' ·   '; do
				printf '\r\033[2K  \033[94m%s\033[0m  %s' "$frame" "$1" >&2
				sleep 0.12
			done
		done
	) &
	SPINNER_PID=$!
}

presentation() {
	if [ -t 2 ] && [ "${TERM:-dumb}" != dumb ] && [ "${NO_COLOR+x}" != x ] && [ "${CI+x}" != x ]; then
		STYLE=1
	fi
	trap 'spinner_stop' EXIT
	trap 'spinner_stop; exit 130' INT
	trap 'spinner_stop; exit 143' TERM
	[ "$QUIET" = 0 ] || return 0
	if [ "$STYLE" = 1 ]; then
		printf '\n  \033[94m◐\033[0m \033[1mlunar\033[0m  \033[90mflight preparation\033[0m\n\n' >&2
	fi
}

usage() {
	cat <<EOF
Lunar installer.

  curl --proto '=https' --tlsv1.2 -sSf https://lunar.estelaz.com/install.sh | sh

It puts a Lunar checkout under $PREFIX, links a launcher into $BIN_DIR, and
builds LuaSocket when your Lua has none. It installs nothing outside your home
directory and never asks for root.

Options:
  --ref REF          branch, tag or commit to install (default: the newest release)
  --from DIR         install from a checkout on this machine instead of fetching
  --prefix DIR       where Lunar goes (default: $PREFIX)
  --bin-dir DIR      where the launcher is linked (default: $BIN_DIR)
  --lua PATH         use this Lua 5.4 rather than looking for one
  --with-lua         build Lua $LUA_VERSION into the prefix, even if one is installed
  --no-socket        do not build LuaSocket; everything but serving still works
  --no-modify-path   do not touch your shell profile
  --uninstall        remove what this installed
  -q, --quiet        say less
  -h, --help         this

Lunar's home is https://lunar.estelaz.com; the source is
https://github.com/$REPO, which is where this fetches from.

Environment: LUNAR_HOME, LUNAR_BIN_DIR, LUNAR_REF, LUNAR_REPO, CC.
Presentation: NO_COLOR disables styling; LUNAR_ANIMATIONS=0 disables animations.
EOF
}

say() {
	[ "$QUIET" = 1 ] && return 0
	spinner_stop
	if [ "$STYLE" = 1 ]; then printf '  \033[94m·\033[0m %s\n' "$1" >&2
	else printf 'lunar: %s\n' "$1" >&2; fi
}
warn() {
	spinner_stop
	if [ "$STYLE" = 1 ]; then printf '  \033[93m!\033[0m %s\n' "$1" >&2
	else printf 'lunar: %s\n' "$1" >&2; fi
}
die() {
	warn "$1"
	exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

parse() {
	while [ $# -gt 0 ]; do
		case $1 in
		--ref)
			REF=${2:?--ref needs a value}
			shift 2
			;;
		--from)
			FROM=${2:?--from needs a directory}
			shift 2
			;;
		--prefix)
			PREFIX=${2:?--prefix needs a directory}
			shift 2
			;;
		--bin-dir)
			BIN_DIR=${2:?--bin-dir needs a directory}
			shift 2
			;;
		--lua)
			LUA_BIN=${2:?--lua needs a path}
			shift 2
			;;
		--with-lua)
			BUILD_LUA=1
			shift
			;;
		--no-socket)
			WANT_SOCKET=0
			shift
			;;
		--no-modify-path)
			MODIFY_PATH=0
			shift
			;;
		--uninstall)
			ACTION=uninstall
			shift
			;;
		-q | --quiet)
			QUIET=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "unknown option $1; try --help" ;;
		esac
	done
}

fetch() {
	spinner_start "Receiving from Earth..."
	fetch_status=0
	if have curl; then
		curl --proto '=https' --tlsv1.2 -fsSL "$1" -o "$2" || fetch_status=$?
	elif have wget; then
		wget -q -O "$2" "$1" || fetch_status=$?
	else
		die "this needs curl or wget"
	fi
	spinner_stop
	return "$fetch_status"
}

newest_release() {
	work=$(mktemp -d)
	tag=
	if fetch "https://api.github.com/repos/$REPO/releases/latest" "$work/release.json" 2>/dev/null; then
		tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$work/release.json" |
			head -1)
	fi
	rm -rf "$work"
	printf '%s' "$tag"
}

resolve_ref() {
	[ -n "$REF" ] && return 0
	REF=$(newest_release || true)
	if [ -z "$REF" ]; then
		REF=main
		warn "could not ask GitHub for the newest release; installing $REF"
	fi
}

sha256_of() {
	if have sha256sum; then
		sha256sum "$1" | cut -d' ' -f1
	elif have shasum; then
		shasum -a 256 "$1" | cut -d' ' -f1
	elif have openssl; then
		openssl dgst -sha256 "$1" | sed 's/.*= //'
	else
		printf ''
	fi
}

verify_sha() {
	actual=$(sha256_of "$1")
	if [ -z "$actual" ]; then
		warn "no sha256 tool here, so $(basename "$1") was taken on trust"
		return 0
	fi
	[ "$actual" = "$2" ] || die "$(basename "$1") is not the file it should be"
}

lua_is_54() { "$1" -v 2>&1 | grep -q 'Lua 5\.4'; }

find_lua() {
	if [ -n "$LUA_BIN" ]; then
		lua_is_54 "$LUA_BIN" || die "$LUA_BIN is not Lua 5.4"
		printf '%s' "$LUA_BIN"
		return
	fi
	if [ -x "$PREFIX/toolchain/bin/lua" ] && lua_is_54 "$PREFIX/toolchain/bin/lua"; then
		printf '%s' "$PREFIX/toolchain/bin/lua"
		return
	fi
	for name in lua5.4 lua54 lua; do
		if have "$name" && lua_is_54 "$name"; then
			command -v "$name"
			return
		fi
	done
	printf ''
}

lua_plat() {
	case $(uname -s) in
	Linux) printf 'linux-noreadline' ;;
	Darwin) printf 'macosx' ;;
	FreeBSD | OpenBSD | NetBSD | DragonFly) printf 'bsd' ;;
	*) printf 'posix' ;;
	esac
}

needs_compiler() {
	have "${CC:-cc}" || have gcc || have clang || die "$1 needs a C compiler"
	have make || die "$1 needs make"
}

build_lua() {
	needs_compiler "building Lua"
	work=$(mktemp -d)
	fetch "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" "$work/lua.tar.gz"
	verify_sha "$work/lua.tar.gz" "$LUA_SHA256"
	mkdir -p "$work/lua"
	tar xzf "$work/lua.tar.gz" -C "$work/lua" --strip-components=1
	say "building Lua $LUA_VERSION"
	spinner_start "Assembling the Lua engine..."
	if ! (cd "$work/lua" && make "$(lua_plat)" >"$work/log" 2>&1); then
		(cd "$work/lua" && make all >"$work/log" 2>&1) || {
			tail -20 "$work/log" >&2
			die "Lua did not build"
		}
	fi
	(cd "$work/lua" && make install INSTALL_TOP="$PREFIX/toolchain" >>"$work/log" 2>&1) ||
		die "Lua built but would not install into $PREFIX/toolchain"
	rm -rf "$work"
	spinner_stop
	printf '%s' "$PREFIX/toolchain/bin/lua"
}

header_dir() {
	for dir in "$PREFIX/toolchain/include" /usr/include/lua5.4 /usr/local/include/lua5.4 \
		/usr/include/lua54 /usr/local/include/lua54 /opt/homebrew/include/lua5.4 \
		/usr/local/include /opt/homebrew/include /usr/include; do
		if [ -f "$dir/lua.h" ] && grep -q 'LUA_VERSION_NUM.*504' "$dir/lua.h" 2>/dev/null; then
			printf '%s' "$dir"
			return
		fi
	done
	printf ''
}

module_paths() {
	share=$PREFIX/modules/share/lua/5.4
	lib=$PREFIX/modules/lib/lua/5.4
}

has_socket() {
	module_paths
	LUA_PATH="$share/?.lua;$share/?/init.lua;;" LUA_CPATH="$lib/?.so;;" \
		"$1" -e 'require("socket")' >/dev/null 2>&1
}

build_luasocket() {
	lua=$1
	needs_compiler "building LuaSocket"
	include=$(header_dir)
	if [ -z "$include" ]; then
		warn "no Lua 5.4 headers found, so LuaSocket cannot be built"
		warn "install them (lua5.4-dev, lua-devel) or rerun with --with-lua"
		return 1
	fi

	work=$(mktemp -d)
	fetch "https://github.com/lunarmodules/luasocket/archive/refs/tags/v$LUASOCKET_VERSION.tar.gz" \
		"$work/luasocket.tar.gz"
	verify_sha "$work/luasocket.tar.gz" "$LUASOCKET_SHA256"
	mkdir -p "$work/luasocket"
	tar xzf "$work/luasocket.tar.gz" -C "$work/luasocket" --strip-components=1

	module_paths
	mkdir -p "$share/socket" "$lib/socket" "$lib/mime"
	compiler=${CC:-cc}
	have "$compiler" || compiler=gcc
	case $(uname -s) in
	Darwin) link="-bundle -undefined dynamic_lookup" ;;
	*) link="-shared" ;;
	esac

	say "building LuaSocket $LUASOCKET_VERSION"
	spinner_start "Connecting the communications module..."
	(
		cd "$work/luasocket/src" &&
			$compiler -O2 -fPIC $link "-I$include" -o "$lib/socket/core.so" \
				luasocket.c timeout.c buffer.c io.c auxiliar.c options.c inet.c except.c \
				select.c tcp.c udp.c usocket.c compat.c &&
			$compiler -O2 -fPIC $link "-I$include" -o "$lib/mime/core.so" mime.c compat.c &&
			cp socket.lua ltn12.lua mime.lua "$share/" &&
			cp http.lua url.lua headers.lua tp.lua ftp.lua smtp.lua "$share/socket/"
	) || {
		rm -rf "$work"
		warn "LuaSocket did not build; everything but serving still works"
		return 1
	}
	rm -rf "$work"
	spinner_stop

	has_socket "$lua" || {
		warn "LuaSocket built but $lua cannot load it"
		return 1
	}
	return 0
}

install_tree() {
	[ -n "$FROM" ] || resolve_ref
	target=$PREFIX/versions/${REF:-main}
	rm -rf "$target"
	mkdir -p "$target"

	if [ -n "$FROM" ]; then
		[ -f "$FROM/lunar/cli.lua" ] || die "$FROM is not a Lunar checkout"
		say "copying $FROM"
		(cd "$FROM" && tar cf - --exclude=./.git --exclude=./.dev --exclude=node_modules .) |
			(cd "$target" && tar xf -)
	else
		say "fetching $REPO at $REF"
		work=$(mktemp -d)
		fetch "https://github.com/$REPO/archive/$REF.tar.gz" "$work/lunar.tar.gz"
		tar xzf "$work/lunar.tar.gz" -C "$target" --strip-components=1
		rm -rf "$work"
	fi

	[ -f "$target/bin/lunar" ] || die "what was installed has no bin/lunar in it"
	chmod +x "$target/bin/lunar"
	rm -f "$PREFIX/current"
	ln -s "$target" "$PREFIX/current"
}

write_launcher() {
	lua=$1
	mkdir -p "$PREFIX/bin"
	cat >"$PREFIX/bin/lunar" <<EOF
#!/bin/sh
set -eu
LUNAR_HOME="$PREFIX"
root="\$LUNAR_HOME/current"
modules="\$LUNAR_HOME/modules"
LUA="\${LUA:-$lua}"
LUA_PATH="\$modules/share/lua/5.4/?.lua;\$modules/share/lua/5.4/?/init.lua;\${LUA_PATH:-;}"
LUA_CPATH="\$modules/lib/lua/5.4/?.so;\${LUA_CPATH:-;}"
export LUA LUA_PATH LUA_CPATH
exec "\$root/bin/lunar" "\$@"
EOF
	chmod +x "$PREFIX/bin/lunar"

	cat >"$PREFIX/env" <<EOF
case ":\${PATH}:" in
*:"$BIN_DIR":*) ;;
*) export PATH="$BIN_DIR:\$PATH" ;;
esac
EOF

	mkdir -p "$BIN_DIR"
	rm -f "$BIN_DIR/lunar"
	ln -s "$PREFIX/bin/lunar" "$BIN_DIR/lunar"
}

update_profile() {
	line=". \"$PREFIX/env\""
	changed=
	for profile in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
		[ -f "$profile" ] || continue
		grep -qF "$PREFIX/env" "$profile" && continue
		printf '\n%s\n' "$line" >>"$profile"
		changed="$changed $(basename "$profile")"
	done
	if [ -z "$changed" ] && [ ! -f "$HOME/.profile" ]; then
		printf '%s\n' "$line" >>"$HOME/.profile"
		changed=" .profile"
	fi
	[ -n "$changed" ] && say "added$changed to your PATH"
	return 0
}

on_path() {
	case ":${PATH}:" in
	*:"$BIN_DIR":*) return 0 ;;
	*) return 1 ;;
	esac
}

install() {
	say "installing into $PREFIX"
	mkdir -p "$PREFIX"

	lua=$(find_lua)
	if [ "$BUILD_LUA" = 1 ] || [ -z "$lua" ]; then
		[ -n "$lua" ] || say "no Lua 5.4 on this machine"
		lua=$(build_lua)
	fi
	lua_release=$("$lua" -v 2>&1 | head -1 | sed 's/  Copyright.*//')
	say "$lua_release  $lua"

	install_tree

	if [ "$WANT_SOCKET" = 1 ]; then
		if has_socket "$lua"; then
			say "luasocket: already there"
		else
			build_luasocket "$lua" && say "luasocket: built into $PREFIX/modules" || true
		fi
	fi

	write_launcher "$lua"
	[ "$MODIFY_PATH" = 1 ] && update_profile

	version=$("$BIN_DIR/lunar" help 2>/dev/null | head -1 || true)
	[ -n "$version" ] || die "the launcher does not run; see $PREFIX"
	say "installed $version"
	if has_socket "$lua"; then
		say "it can serve: LuaSocket is in place"
	else
		say "it cannot serve yet: LuaSocket is missing, everything else works"
	fi

	if ! on_path; then
		say "$BIN_DIR is not on your PATH yet; open a new shell, or run:"
		say "  . \"$PREFIX/env\""
	fi
	say "try: lunar dev $PREFIX/current/examples/tranquility"
	if [ "$STYLE" = 1 ] && [ "$QUIET" = 0 ]; then
		printf '\n  \033[94m●\033[0m \033[1mReady for orbit.\033[0m\n\n' >&2
	fi
}

uninstall() {
	[ -d "$PREFIX" ] || [ -L "$BIN_DIR/lunar" ] || die "nothing is installed in $PREFIX"
	rm -f "$BIN_DIR/lunar"
	rm -rf "$PREFIX"
	say "removed $PREFIX and $BIN_DIR/lunar"
	for profile in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
		[ -f "$profile" ] || continue
		if grep -qF "$PREFIX/env" "$profile"; then
			say "take this line out of $profile: . \"$PREFIX/env\""
		fi
	done
}

parse "$@"
presentation
case $ACTION in
install) install ;;
uninstall) uninstall ;;
esac
