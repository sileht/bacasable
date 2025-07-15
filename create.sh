#!/bin/bash

mkdir .github/dyn-action
cat > .github/workflow/dyn-action.yml << EOF
name: Mergify CI

on:
  workflow_call:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/workflows/javascript.yaml
      - uses: ./.github/workflows/python.yaml
EOF
