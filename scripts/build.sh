#!/bin/bash
set -e

echo "Building app-intents-mcp..."

# Build universal binary
swift build -c release --arch arm64 --arch x86_64

echo "Build complete: .build/apple/Products/Release/app-intents-mcp"
