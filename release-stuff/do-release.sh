#!/usr/bin/env bash

set -o errexit
set -o pipefail

###############################################################################
# Determine script dir
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


###############################################################################
# Retrieve command line arguments

if [ $# -lt 2 ]; then
    echo 'You need to pass:'
    echo '   - a version'
    echo '   - a CircleCI token'
    exit 1
fi

VERSION=$1
TOKEN=$2
RAKUBREW_SERVER_SSH_CON=$USER@raku-infra-fsn1-03.rakulang.site
ARM_MAC_SSH_CON=administrator@207.254.31.127
CIRCLECI_BUILD_FILE=rakubrew.tgz
SERVER_RELEASE_DIR=/data/dockervolume/rakubrew.org/releases
ARM_MAC_REMOTE_PATH=/Users/administrator/repos/App-Rakubrew

echo 
read -p "Did you write the changes in Changes? [YyNn]" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Exitting"
    exit 1
fi

###############################################################################
# Prepare files

pushd $DIR/..
perl -pi -e "s/^our \\\$VERSION = '\\d+';$/our \\\$VERSION = '$VERSION';/" lib/App/Rakubrew.pm
dzil regenerate
git commit -a -m "Version $VERSION"
git tag v$VERSION

###############################################################################
# Upload to Git server

git push origin master v$VERSION

###############################################################################
# CPAN release

dzil release

popd

###############################################################################
# Trigger CircleCI build
curl \
-u $TOKEN: \
-X POST \
-H 'Content-Type: application/json' \
-d "{
  \"parameters\": {
    \"MANUAL_BUILD\": true,
    \"VERSION\": \"$VERSION\"
  }
}" \
https://circleci.com/api/v2/project/gh/Raku/App-Rakubrew/pipeline

###############################################################################
# Do the MacOS Arm build
rm -r macos_arm || true
mkdir macos_arm
ssh $ARM_MAC_SSH_CON "\
    rm $ARM_MAC_REMOTE_PATH/rakubrew;\
    git -C $ARM_MAC_REMOTE_PATH pull &&\
    $ARM_MAC_REMOTE_PATH/release-stuff/build-macos.sh"
scp $ARM_MAC_SSH_CON:$ARM_MAC_REMOTE_PATH/rakubrew $DIR/macos_arm/rakubrew

###############################################################################
# Prompt user for CircleCI build files
rm rakubrew.tgz || true
echo "Build started. Now look at https://circleci.com/gh/Raku/workflows/App-Rakubrew/tree/master"
echo "wait for completion and download the $CIRCLECI_BUILD_FILE release artifact and place it in the release-stuff/$CIRCLECI_BUILD_FILE folder."
read -p "Then continue the build here. Press y to continue."
while true
do
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		if [ -f $CIRCLECI_BUILD_FILE ]
		then
			break
		fi
	fi
done

###############################################################################
# Finish preparing the release files
rm -rf $VERSION || true
tar -xzf $CIRCLECI_BUILD_FILE
rm $CIRCLECI_BUILD_FILE
mv macos_arm $VERSION/macos_arm
cp ../Changes $VERSION/changes
perl -ni -e "BEGIN {my \$p=0;}  if (/^$VERSION\$/){\$p=1} elsif (/^\\d+\$/){\$p=0} elsif (\$p){print substr(\$_, 4)}" $VERSION/changes

###############################################################################
# Deploy to the server
REL_FILE=rakubrew-$VERSION.tgz
tar -czv --owner=0 --group=0 --numeric-owner -f $REL_FILE $VERSION
scp $REL_FILE $RAKUBREW_SERVER_SSH_CON:~
ssh $RAKUBREW_SERVER_SSH_CON "sudo tar -C $SERVER_RELEASE_DIR -xzf ~/$REL_FILE && rm ~/$REL_FILE"

###############################################################################
# Clean up
rm $REL_FILE
rm -rf $VERSION

