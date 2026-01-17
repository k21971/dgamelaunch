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

set -e

umask 022

DGL_BIN="$DGL_GIT/dgamelaunch"
if [ -n "$DGL_BIN" -a ! -e "$DGL_BIN" ]; then
  errorexit "Cannot find dgl binary $DGL_BIN"
fi

if [ -n "$DGL_BIN" -a -e "$DGL_BIN" ]; then
  echo "Copying $DGL_BIN"
  cd "$NAO_CHROOT"
  DGLBINFILE="`basename $DGL_BIN`-$DATESTAMP"
  cp "$DGL_BIN" "$DGLBINFILE"
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
    cp "$BINARY_PATH" "$CHROOT_BIN/$binary"
    chmod 755 "$CHROOT_BIN/$binary"
    LIBS="$LIBS `findlibs $BINARY_PATH`"
  else
    echo "Warning: $binary not found at $BINARY_PATH - skipping."
  fi
done

LIBS=`for lib in $LIBS; do echo $lib; done | sort | uniq`
echo "Copying libraries:" $LIBS
for lib in $LIBS; do
        mkdir -p "$NAO_CHROOT`dirname $lib`"
        if [ -f "$NAO_CHROOT$lib" ]
	then
		echo "$NAO_CHROOT$lib already exists - skipping."
	else
		cp $lib "$NAO_CHROOT$lib"
	fi
done

echo "Finished."

