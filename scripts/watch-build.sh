#!/bin/bash
# Build-only watcher - just compiles, doesn't run

echo "🔨 Starting build-only watcher..."
echo "📁 Watching: src/, examples/, tests/"
echo "🔧 Auto-build on: *.zig files"
echo "⚡ Fast feedback for compilation errors"
echo ""
echo "Press Ctrl+C to stop"
echo ""

watchexec \
    --clear \
    --exts=zig \
    --ignore-paths=zig-cache,zig-out \
    --watch=src \
    --watch=examples \
    --watch=tests \
    -- bash -c 'echo "🔍 Checking compilation..." && zig build check && echo "✅ Compilation OK" && echo "🔨 Building demo_app..." && zig build demo_app && echo "✅ Build complete"'