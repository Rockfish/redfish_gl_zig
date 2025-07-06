#!/bin/bash
# Development watcher - rebuilds and runs on any Zig file change

echo "🔄 Starting development watcher..."
echo "📁 Watching: src/, examples/, tests/"
echo "🔧 Auto-rebuild on: *.zig files"
echo "🎮 Auto-run: demo_app"
echo ""
echo "Press Ctrl+C to stop"
echo "Use 'n' and 'b' in demo to cycle models"
echo ""

watchexec \
    --clear \
    --restart \
    --exts=zig \
    --ignore-paths=zig-cache,zig-out \
    --watch=src \
    --watch=examples \
    --watch=tests \
    -- bash -c 'echo "🔨 Building..." && zig build demo_app && echo "🚀 Starting demo..." && zig build demo_app-run'