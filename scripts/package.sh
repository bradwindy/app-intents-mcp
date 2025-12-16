#!/bin/bash
set -e

echo "Packaging app-intents-mcp.mcpb..."

# Build first
./scripts/build.sh

# Create staging directory
rm -rf .package
mkdir -p .package/bin

# Copy binary
cp .build/apple/Products/Release/app-intents-mcp .package/bin/

# Copy manifest and README
cp manifest.json .package/
cp README.md .package/

# Create mcpb (zip archive)
cd .package
zip -r ../app-intents-mcp.mcpb .
cd ..

# Cleanup
rm -rf .package

echo "Package created: app-intents-mcp.mcpb"
