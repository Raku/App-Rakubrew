#!/usr/bin/env sh

if [ $# -lt 1 ]; then
    echo 'You need to pass:'
    echo '   - a CircleCI token'
    exit 1
fi

curl \
-u $1: \
-X POST \
-H 'Content-Type: application/json' \
-d "{
  \"parameters\": {
    \"MANUAL_BUILD\": true
  }
}" \
https://circleci.com/api/v2/project/gh/Raku/App-Rakubrew/pipeline

