#!/bin/bash
#
# Ideas and some parts from the original dgl-create-chroot (by joshk@triplehelix.org, modifications by jilles@stack.nl)
# More by <paxed@alt.org>
# More by Michael Andrew Streib <dtype@dtype.org>
# Licensed under the MIT License
# https://opensource.org/licenses/MIT

# autonamed dgl binary. Symlink points to this.
DATESTAMP=`date +%Y%m%d-%H%M%S`
NAO_CHROOT="/opt/nethack/chroot"
# dgl has been compiled in this directory
DGL_GIT="/home/build/dgamelaunch"
# the user & group from dgamelaunch config file.
USRGRP="games:games"
# END OF CONFIG
##############################################################################

errorexit()
{
    echo "Error: $@" >&2
    exit 1
}

findlibs()
{
  for i in "$@"; do
      if [ -z "`ldd "$i" | grep 'not a dynamic executable'`" ]; then
         echo $(ldd "$i" | awk '{ print $3 }' | egrep -v ^'\(' | grep lib)
         echo $(ldd "$i" | grep 'ld-linux' | awk '{ print $1 }')
      fi
  done
}

# Temp files created by install_atomic, removed by the EXIT trap so an aborted
# run (set -e) never leaves half-copied files behind in the chroot. Tracked as
# a list rather than globbed per-directory, since libraries land in several
# directories (/lib/x86_64-linux-gnu, /lib64, ...) besides the bin directory.
TMPFILES=()

cleanup_tmpfiles()
{
    if [ ${#TMPFILES[@]} -gt 0 ]; then
        rm -f "${TMPFILES[@]}"
    fi
    return 0
}

# Atomically replace $2 with a copy of $1, optionally forcing mode $3.
#
# Copying directly onto a live file is unsafe in two different ways:
#   - executables: cp fails outright with ETXTBSY ("Text file busy") if any
#     process is currently executing the target -- e.g. a player sitting in
#     the virus editor, or a long-running frotz session.
#   - shared libraries: cp SUCCEEDS with no error at all and rewrites pages
#     underneath processes that have the library mapped. Silent, and so worse
#     than the failure above.
#
# Copying to a temp name in the same directory and then rename(2)ing over the
# target avoids both: the swap is atomic, and any process still using the old
# file keeps its inode until it exits. The temp must share a directory with
# the target so that mv is a true rename and not a copy-then-unlink.
install_atomic()
{
    local src="$1" dest="$2" mode="${3:-}" tmp="$2.new.$$"
    TMPFILES+=("$tmp")
    cp "$src" "$tmp"
    if [ -n "$mode" ]; then
        chmod "$mode" "$tmp"
    fi
    mv -f "$tmp" "$dest"
}

# Executables get an explicit 755. Libraries call install_atomic directly with
# no mode, keeping whatever cp gives them (source mode masked by umask) --
# which is exactly what the original non-atomic library copy produced.
install_binary()
{
    install_atomic "$1" "$2" 755
}

usage()
{
    cat <<EOF
Usage: $0 [--update-libs]

Installs dgamelaunch and its helper binaries (ee, virus, frotz) into the
chroot at $NAO_CHROOT.

Shared libraries are compared against the host copies on every run. Libraries
missing from the chroot are always installed. Libraries that are present but
differ from the host are only REPORTED by default; pass --update-libs to
actually refresh them.
EOF
}

UPDATE_LIBS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --update-libs) UPDATE_LIBS=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)             usage >&2; errorexit "Unknown argument: $1" ;;
    esac
    shift
done

set -e

umask 022

trap cleanup_tmpfiles EXIT

DGL_BIN="$DGL_GIT/dgamelaunch"
if [ -n "$DGL_BIN" -a ! -e "$DGL_BIN" ]; then
  errorexit "Cannot find dgl binary $DGL_BIN"
fi

if [ -n "$DGL_BIN" -a -e "$DGL_BIN" ]; then
  echo "Copying $DGL_BIN"
  cd "$NAO_CHROOT"
  DGLBINFILE="`basename $DGL_BIN`-$DATESTAMP"
  cp "$DGL_BIN" "$DGLBINFILE"
  # Mode is set explicitly rather than left to whatever cp happens to produce.
  # 755, NOT 4755: here dgamelaunch is invoked as root and sheds privileges
  # itself (dgamelaunch.c: chroot(), then setgroups/setgid/setuid), so it does
  # not need the setuid bit. README section 4a -- running it as a setuid-root
  # login shell instead -- would require 4755, and note that cp without -p
  # silently clears that bit, so switching to that setup means setting it here.
  chmod 755 "$DGLBINFILE"
  ln -fs "$DGLBINFILE" dgamelaunch
  LIBS="$LIBS `findlibs $DGL_BIN`"
fi

# Copy helper binaries to chroot bin directory
CHROOT_BIN="$NAO_CHROOT/bin"
mkdir -p "$CHROOT_BIN"

for binary in ee virus; do
  BINARY_PATH="$DGL_GIT/$binary"
  if [ -e "$BINARY_PATH" ]; then
    echo "Copying $binary to $CHROOT_BIN/"
    install_binary "$BINARY_PATH" "$CHROOT_BIN/$binary"
    LIBS="$LIBS `findlibs $BINARY_PATH`"
  else
    echo "Warning: $binary not found at $BINARY_PATH - skipping."
  fi
done

# Patched frotz with font 3 support (lives in bin/ subdirectory)
FROTZ_PATH="$DGL_GIT/bin/frotz"
if [ -e "$FROTZ_PATH" ]; then
  echo "Copying frotz to $CHROOT_BIN/"
  install_binary "$FROTZ_PATH" "$CHROOT_BIN/frotz"
  LIBS="$LIBS `findlibs $FROTZ_PATH`"
else
  echo "Warning: frotz not found at $FROTZ_PATH - skipping."
fi

LIBS=`for lib in $LIBS; do echo $lib; done | sort | uniq`

# Compare every host library against the chroot's copy. The previous version of
# this loop skipped anything already present, so a chroot could silently fall
# behind the host (e.g. after an apt upgrade bumped libncursesw) while the
# deploy still reported success -- surfacing much later as a missing-symbol
# abort at runtime. Now: missing libraries are installed, differing ones are
# reported, and --update-libs is required to actually replace them.
#
# ldd reports symlink paths (libncursesw.so.6 -> libncursesw.so.6.4); both cp
# and cmp dereference, so the chroot holds a regular file and the comparison is
# content-to-content. Do not "fix" this with cp -P/-d -- that would leave a
# dangling symlink inside the chroot.
echo "Checking libraries:" $LIBS
LIBS_SAME=0
LIBS_ADDED=0
LIBS_DRIFT=0
DRIFTED=""
for lib in $LIBS; do
	dest="$NAO_CHROOT$lib"
	mkdir -p "$(dirname "$dest")"
	if [ ! -f "$dest" ]; then
		echo "  adding $lib"
		install_atomic "$lib" "$dest"
		LIBS_ADDED=$((LIBS_ADDED + 1))
	elif cmp -s "$lib" "$dest"; then
		LIBS_SAME=$((LIBS_SAME + 1))
	else
		LIBS_DRIFT=$((LIBS_DRIFT + 1))
		DRIFTED="$DRIFTED $lib"
		if [ "$UPDATE_LIBS" -eq 1 ]; then
			echo "  updating $lib (differed from host)"
			install_atomic "$lib" "$dest"
		else
			echo "  DRIFT: $lib differs from the chroot copy"
		fi
	fi
done

if [ "$UPDATE_LIBS" -eq 1 ]; then
	echo "Libraries: $LIBS_SAME up to date, $LIBS_ADDED added, $LIBS_DRIFT updated."
else
	echo "Libraries: $LIBS_SAME up to date, $LIBS_ADDED added, $LIBS_DRIFT differing."
fi

if [ "$LIBS_DRIFT" -gt 0 ] && [ "$UPDATE_LIBS" -eq 0 ]; then
	echo
	echo "The chroot has drifted from the host for:$DRIFTED"
	echo "Re-run with --update-libs to refresh them."
fi

echo "Finished."

