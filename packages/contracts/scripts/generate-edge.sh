#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pinned: protoc 36.2; protoc-gen-go 1.36.11; protoc-gen-go-grpc 1.6.2;
# protoc-gen-dart (protoc_plugin) 25.0.0. See apps/edge/README.md.
[[ "$(protoc --version)" == 'libprotoc 36.2' ]] || { echo 'protoc 36.2 required' >&2; exit 1; }
[[ "$(protoc-gen-go --version)" == 'protoc-gen-go v1.36.11' ]] || exit 1
[[ "$(protoc-gen-go-grpc --version)" == 'protoc-gen-go-grpc 1.6.2' ]] || exit 1
dart_tools=$(dart pub global list)
[[ "$dart_tools" == *"protoc_plugin 25.0.0"* ]] || { echo 'protoc_plugin 25.0.0 required' >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/go" "$tmp/dart"
protoc -I proto --go_out="$tmp/go" --go_opt=paths=source_relative --go-grpc_out="$tmp/go" --go-grpc_opt=paths=source_relative --dart_out="grpc:$tmp/dart" proto/vynic/edge/v1/foundation.proto
if [[ "${1:-}" == '--check' ]]; then
  diff -ru generated/go/vynic "$tmp/go/vynic"
  diff -ru generated/edge_dart/lib/src/generated "$tmp/dart"
else
  cp -R "$tmp/go/." generated/go/
  cp -R "$tmp/dart/." generated/edge_dart/lib/src/generated/
fi
