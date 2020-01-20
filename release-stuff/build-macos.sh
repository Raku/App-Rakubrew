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

cp resources/Config.pm.tmpl lib/App/Rakubrew/Config.pm
perl -pi -E 's/<\%distro_format\%>/fatpack/' lib/App/Rakubrew/Config.pm

mkdir download
mkdir strawberry

cpanm -n PAR::Packer
cpanm --installdeps -n .
cpanm --installdeps -n --cpanfile cpanfile.macos .

pp -I lib -M App::Rakubrew::Shell::* -M IO::Socket::SSL -o rakubrew script/rakubrew

