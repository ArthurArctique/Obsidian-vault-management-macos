#!/usr/bin/env bash
# run_tests.sh — Compile et lance les tests de la liste des vaults et de obsidian.json.
# Les tests travaillent dans un dossier temporaire : ni la vraie liste ni Obsidian ne sont touchés.
set -euo pipefail

cd "$(dirname "$0")/.."

TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/obsivaults-tests.XXXXXX")"
trap 'rm -rf "${TEST_TMP}"' EXIT

swiftc \
    Sources/ObsidianRegistry.swift \
    Sources/VaultStore.swift \
    Tests/main.swift \
    -swift-version 5 \
    -o "${TEST_TMP}/ObsiVaultsTests"

OBSIVAULTS_TEST_DIR="${TEST_TMP}/work" "${TEST_TMP}/ObsiVaultsTests"
