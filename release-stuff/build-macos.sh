#!/usr/bin/env bash

set -o errexit
set -o pipefail

# Sourced from https://stackoverflow.com/a/29835459/1975049
rreadlink() (
  target=$1 fname= targetDir= CDPATH=
  { \unalias command; \unset -f command; } >/dev/null 2>&1
  [ -n "$ZSH_VERSION" ] && options[POSIX_BUILTINS]=on
  while :; do
      [ -L "$target" ] || [ -e "$target" ] || { command printf '%s\n' "ERROR: '$target' does not exist." >&2; return 1; }
      command cd "$(command dirname -- "$target")" || exit 1
      fname=$(command basename -- "$target")
      [ "$fname" = '/' ] && fname=''
      if [ -L "$fname" ]; then
        target=$(command ls -l "$fname")
        target=${target#* -> }
        continue
      fi
      break
  done
  targetDir=$(command pwd -P)
  if [ "$fname" = '.' ]; then
    command printf '%s\n' "${targetDir%/}"
  elif  [ "$fname" = '..' ]; then
    command printf '%s\n' "$(command dirname -- "${targetDir}")"
  else
    command printf '%s\n' "${targetDir%/}/$fname"
  fi
)

EXEC=$(rreadlink "$0")
DIR=$(dirname -- "$EXEC")

ARCH=$(uname -m)
if [[ $ARCH != "arm64" ]]; then
  # ARCH is probably x86_64 here, but the download links for that arch
  # contain the string 'amd64'.
  ARCH="amd64"
fi

# ============================================
# Actual script starts here

cd $DIR/..

# Download precompiled perl.
if ! [ -d download ]; then
    mkdir download
fi
unset PERL5LIB
if ! [ -d $DIR/../perl-darwin-$ARCH ]; then
    curl -L -o download/perl-precomp.tar.gz https://github.com/skaji/relocatable-perl/releases/download/5.36.0.1/perl-darwin-$ARCH.tar.gz
    tar -xzf download/perl-precomp.tar.gz
fi
export PATH=$DIR/../perl-darwin-$ARCH/bin:$PATH

# Prepare Config.pm
cp resources/Config.pm.tmpl lib/App/Rakubrew/Config.pm
perl -pi -E 's/<\%distro_format\%>/macos/' lib/App/Rakubrew/Config.pm

# Install dependencies
cpanm -n PAR::Packer
cpanm --installdeps -n .
cpanm --installdeps -n --cpanfile cpanfile.macos .

# PAR package rakubrew
pp -I lib -M App::Rakubrew:: -M HTTP::Tinyish:: -M IO::Socket::SSL -o rakubrew script/rakubrew

# Reset our modified Config.pm again.
git checkout -f lib/App/Rakubrew/Config.pm
