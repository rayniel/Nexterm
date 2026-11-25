#!/usr/bin/env bash
# Build a local Nexterm all-in-one image from this checkout.
# Usage: ./build-local.sh [tag]   (default: nexterm-remix:latest)
# Env:   ENGINE_IMAGE  prebuilt engine image to reuse (default: nexterm/engine:latest)
#        BUILD_ENGINE=1 build the engine from source instead (slow)
#        PLATFORM       e.g. linux/amd64 (default: host platform)
set -euo pipefail

cd "$(dirname "$0")"

TAG="${1:-nexterm-remix:latest}"
ENGINE_IMAGE="${ENGINE_IMAGE:-nexterm/engine:latest}"
SERVER_IMAGE="nexterm-remix-server:local"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' package.json | head -n1)"
PLATFORM_ARGS=()
[ -n "${PLATFORM:-}" ] && PLATFORM_ARGS=(--platform "$PLATFORM")

if [ "${BUILD_ENGINE:-0}" = "1" ]; then
    ENGINE_IMAGE="nexterm-remix-engine:local"
    echo ">> Building engine -> $ENGINE_IMAGE"
    docker build "${PLATFORM_ARGS[@]}" -f Dockerfile.engine -t "$ENGINE_IMAGE" .
else
    echo ">> Pulling engine $ENGINE_IMAGE"
    docker pull "${PLATFORM_ARGS[@]}" "$ENGINE_IMAGE"
fi

echo ">> Building server -> $SERVER_IMAGE (version $VERSION)"
docker build "${PLATFORM_ARGS[@]}" -f Dockerfile.server \
    --build-arg VERSION="$VERSION" -t "$SERVER_IMAGE" .

echo ">> Building all-in-one -> $TAG"
docker build "${PLATFORM_ARGS[@]}" -f Dockerfile \
    --build-arg SERVER_IMAGE="$SERVER_IMAGE" \
    --build-arg ENGINE_IMAGE="$ENGINE_IMAGE" \
    -t "$TAG" .

echo ">> Done. Run with:"
echo "   docker run -d --name nexterm --network host -v nexterm-data:/app/data $TAG"
