#!/bin/bash
set -e

cd "$(dirname "$0")"
source ./canvas-common.sh

ensure_canvas_components

cd canvas_components
npx canvas-workbench
