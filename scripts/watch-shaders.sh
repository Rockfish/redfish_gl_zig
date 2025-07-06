#!/bin/bash
# Shader development watcher - validates and rebuilds on shader changes

echo "🎨 Starting shader development watcher..."
echo "📁 Watching: examples/demo_app/shaders/"
echo "🔧 Auto-validate on: *.vert, *.frag files"
echo "🎮 Auto-rebuild and run demo on changes"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Check if glslangValidator is available
if ! command -v glslangValidator &> /dev/null; then
    echo "⚠️  glslangValidator not found. Install with:"
    echo "   brew install glslang"
    echo ""
    echo "Continuing without shader validation..."
    VALIDATE_CMD="echo '⚠️  Skipping shader validation'"
else
    VALIDATE_CMD="echo '🔍 Validating shaders...' && find examples/demo_app/shaders -name '*.vert' -o -name '*.frag' | xargs -I {} sh -c 'echo \"Checking {}...\" && glslangValidator \"{}\"'"
fi

watchexec \
    --clear \
    --restart \
    --exts=vert,frag,zig \
    --ignore-paths=zig-cache,zig-out \
    --watch=examples/demo_app/shaders \
    --watch=src \
    --watch=examples/demo_app \
    -- bash -c "$VALIDATE_CMD && echo '🔨 Building...' && zig build demo_app && echo '🚀 Starting demo...' && zig build demo_app-run"