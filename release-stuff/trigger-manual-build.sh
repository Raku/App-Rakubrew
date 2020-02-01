#!/usr/bin/env sh

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

