#!/bin/sh
# Run the busted suite on Linux (test.cmd is the Windows equivalent).
#
# busted lives in the Lua 5.1 rocks tree while the system `lua` is 5.5, so both
# the interpreter and the rocks paths have to be pinned: the launcher script
# would otherwise resolve 5.5 paths and fail to load LuaFileSystem, and busted
# re-execs whatever `--lua` names for the test run itself.
set -e

LUA=${LUA:-/usr/bin/lua5.1}
ROCKS=${ROCKS:-$HOME/.luarocks}

cd "$(dirname "$0")"

runner=$(mktemp)
trap 'rm -f "$runner"' EXIT
echo 'require("busted.runner")({standalone=false})' > "$runner"

LUA_PATH="$ROCKS/share/lua/5.1/?.lua;$ROCKS/share/lua/5.1/?/init.lua;./lua/?.lua;./lua/?/init.lua;./?.lua;;" \
LUA_CPATH="$ROCKS/lib/lua/5.1/?.so;;" \
  "$LUA" "$runner" --lua="$LUA" "$@"
