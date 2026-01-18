#!/usr/bin/env bash
# Compatibility shim for Bats "load".
# Some Bats versions look for .bash when given a bare path.

source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
