#!/bin/bash
set -e

cd "$(dirname "$0")/canvas_components"

npm i
npx canvas-workbench
