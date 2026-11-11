#!/usr/bin/env bash
# Installs lua5.1 and/or protoc without apt: the Ubuntu mirrors were
# unreachable from the runners (11.11.), so both come from their own
# upstream downloads.  Usage: toolchain.sh lua protoc
set -euo pipefail
tmp="$(mktemp -d)"
get() { curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors -o "$2" "$1"; }
# lua.org drops a connection now and then (11.11.): its official mirror next, the checksum decides
getany() { local out="$1"; shift; for u in "$@"; do get "$u" "$out" && return 0; echo "download failed: $u" >&2; done; return 1; }
for tool in "$@"; do
  case "$tool" in
    lua)
      getany "$tmp/lua.tgz" https://www.lua.org/ftp/lua-5.1.5.tar.gz https://www.tecgraf.puc-rio.br/lua/ftp/lua-5.1.5.tar.gz
      echo "2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333  $tmp/lua.tgz" | sha256sum -c -
      tar -xzf "$tmp/lua.tgz" -C "$tmp"
      make -s -C "$tmp/lua-5.1.5" posix >/dev/null
      sudo install -m 755 "$tmp/lua-5.1.5/src/lua" /usr/bin/lua5.1
      lua5.1 -v ;;
    protoc)
      v=29.3
      get "https://github.com/protocolbuffers/protobuf/releases/download/v$v/protoc-$v-linux-x86_64.zip" "$tmp/protoc.zip"
      sudo unzip -qo "$tmp/protoc.zip" -d /usr/local bin/protoc 'include/*'
      sudo chmod 755 /usr/local/bin/protoc
      protoc --version ;;
    *) echo "unknown tool $tool" >&2; exit 2 ;;
  esac
done
