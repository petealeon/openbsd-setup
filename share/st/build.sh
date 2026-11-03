#!/bin/sh
# build.sh — fetch, patch, build and install st for the amber desktop.
#
#   doas sh share/st/build.sh          build and install into /usr/local
#   sh share/st/build.sh --check       only verify the tarball and patches
#   ST_BUILD_DIR=/tmp/st sh ...        build somewhere else
#   ST_VERSION=0.9.3 sh ...            different upstream release
#
# OpenBSD notes:
#   * st's Makefile uses $(shell ...), so it needs gmake, not base make.
#   * X11 and Xft headers come from xenocara (base); freetype and fontconfig
#     come from packages (they are listed in packages.txt).
#   * the alpha patch does not apply to 0.9.2 and is not used; picom handles
#     terminal transparency instead.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VERSION=${ST_VERSION:-0.9.2}
BUILD=${ST_BUILD_DIR:-/usr/obj/st-$VERSION}
PREFIX=${ST_PREFIX:-/usr/local}
URL="https://dl.suckless.org/st/st-$VERSION.tar.gz"
SHA_FILE="$REPO/share/st/SHA256"
SRC="$BUILD/st-$VERSION"
PATCHES="$REPO/share/st/patches"
CHECK_ONLY=0

for arg in "$@"; do
	case $arg in
	--check) CHECK_ONLY=1 ;;
	-h|--help)
		sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "usage: ${0##*/} [--check]" >&2
		exit 2
		;;
	esac
done

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "$PATCHES/st-scrollback-$VERSION.diff" ] ||
	die "no patch set for st $VERSION in $PATCHES"

if [ "$CHECK_ONLY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
	die "installing st needs root: doas sh $0"
fi
command -v gmake >/dev/null 2>&1 ||
	die "gmake is required (pkg_add gmake)"
# st's config.mk says CC = c99, which OpenBSD 8.0 no longer ships; base is cc.
command -v cc >/dev/null 2>&1 || die "no C compiler: cc is missing"
CC=${CC:-cc}

say "st $VERSION -> $PREFIX (build dir $BUILD)"
mkdir -p "$BUILD"

# ── fetch and verify ───────────────────────────────────────────────────────
tarball="$BUILD/st-$VERSION.tar.gz"
if [ ! -f "$tarball" ]; then
	say "fetching $URL"
	if command -v ftp >/dev/null 2>&1; then
		ftp -o "$tarball" "$URL" || die "download failed"
	elif command -v curl >/dev/null 2>&1; then
		curl -sSfL -o "$tarball" "$URL" || die "download failed"
	else
		die "neither ftp(1) nor curl is available"
	fi
fi

want=$(sed -n 1p "$SHA_FILE")
got=$(sha256 -q "$tarball" 2>/dev/null || sha256sum "$tarball" | cut -d' ' -f1)
[ "$want" = "$got" ] || die "sha256 mismatch for $tarball
  expected $want
  got      $got"
say "sha256 ok"

# ── extract and patch ──────────────────────────────────────────────────────
rm -rf "$SRC"
tar -C "$BUILD" -xzf "$tarball" || die "extracting $tarball failed"
cd "$SRC"

install -m 644 "$REPO/share/st/config.h" config.h
say "config.h: BlexMono Nerd Font pixelsize 18, amber palette"

for p in "$PATCHES"/*.diff; do
	[ -f "$p" ] || continue
	printf '    %-34s ' "$(basename "$p")"
	if patch -p1 -F3 -s <"$p"; then
		echo ok
	else
		echo FAILED
		die "$(basename "$p") does not apply to st $VERSION"
	fi
done

[ "$CHECK_ONLY" -eq 1 ] && { say "patches apply; stopping (--check)"; exit 0; }

# ── build and install ──────────────────────────────────────────────────────
# xenocara ships freetype and fontconfig in base, but there are no .pc files
# to discover them with, so the include and link flags are explicit instead of
# going through pkg-config.
say "building"
log="$BUILD/build.log"
# Note: a pipeline would hide gmake's exit status (POSIX sh has no
# pipefail), so the log is captured and checked instead.
if ! gmake CC="$CC" \
	INCS="-I/usr/X11R6/include -I/usr/X11R6/include/freetype2" \
	LIBS="-L/usr/X11R6/lib -lm -lX11 -lutil -lXft -lfontconfig -lfreetype" \
	>"$log" 2>&1; then
	sed 's/^/    /' "$log" | tail -30
	die "build failed (log: $log)"
fi
sed 's/^/    /' "$log" | tail -3

say "installing (PREFIX=$PREFIX)"
if ! gmake install CC="$CC" PREFIX="$PREFIX" MANPREFIX="$PREFIX/man" \
	>"$log.install" 2>&1; then
	sed 's/^/    /' "$log.install" | tail -20
	die "install failed (log: $log.install)"
fi

[ -x "$PREFIX/bin/st" ] || die "st was not installed at $PREFIX/bin/st"

# st.info is installed by 'make install'; prove the entry landed.
if command -v infocmp >/dev/null 2>&1; then
	infocmp st-256color >/dev/null 2>&1 ||
		die "st-256color terminfo not installed; check TERMINFO/tic"
fi

say "done: $("$PREFIX/bin/st" -v 2>&1 | sed -n 1p)"
