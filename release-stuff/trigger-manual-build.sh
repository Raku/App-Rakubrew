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

if [ $# -lt 2 ]; then
    echo 'You need to pass:'
    echo '   - a version'
    echo '   - a CircleCI token'
    exit 1
fi

curl \
-u $2: \
-X POST \
-H 'Content-Type: application/json' \
-d "{
  \"parameters\": {
    \"MANUAL_BUILD\": true,
    \"VERSION\": \"$1\"
  }
}" \
https://circleci.com/api/v2/project/gh/Raku/App-Rakubrew/pipeline

# Do the MacOS Arm build
rm -r $DIR/macos_arm || true
mkdir $DIR/macos_arm
REMOTE_PATH=/Users/administrator/repos/App-Rakubrew
ssh administrator@207.254.31.127 "\
    rm $REMOTE_PATH/rakubrew;\
    git -C $REMOTE_PATH pull &&\
    $REMOTE_PATH/release-stuff/build-macos.sh"

scp administrator@207.254.31.127:$REMOTE_PATH/rakubrew $DIR/macos_arm/rakubrew
