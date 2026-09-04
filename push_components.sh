#!/bin/bash
set -e

cd "$(dirname "$0")/canvas_components"

npm i

set -a
source .env
set +a

npx canvas login --site-url "$CANVAS_SITE_URL" --client-id "$CANVAS_CLIENT_ID"
npx canvas push
