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


# ============================================
# Actual script starts here

cd $DIR/..

# Download precompiled perl.
mkdir download
unset PERL5LIB
curl -L -o download/perl-precomp.tar.gz https://github.com/skaji/relocatable-perl/releases/download/5.26.1.1/perl-darwin-2level.tar.gz
tar -xzf download/perl-precomp.tar.gz
export PATH=$DIR/../perl-darwin-2level/bin:$PATH

# Prepare Config.pm
cp resources/Config.pm.tmpl lib/App/Rakubrew/Config.pm
perl -pi -E 's/<\%distro_format\%>/macos/' lib/App/Rakubrew/Config.pm

# Install dependencies
cpanm -n PAR::Packer
cpanm --installdeps -n .
cpanm --installdeps -n --cpanfile cpanfile.macos .

# PAR package rakubrew
pp -I lib -M App::Rakubrew:: -M HTTP::Tinyish:: -M IO::Socket::SSL -o rakubrew script/rakubrew

