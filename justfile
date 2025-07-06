# redfish_gl_zig development recipes

# Default recipe - show available commands
default:
    @just --list

# Development workflow
build: check
    zig build demo_app

run: build
    zig build demo_app-run

# Development with auto-rebuild on file changes
dev:
    watchexec --clear --restart --exts=zig,vert,frag -- just run

# Quick compilation check without building
check:
    zig build check

# Code formatting
fmt:
    zig fmt src/ examples/ tests/

# Testing
test: test-movement test-glb

test-movement:
    zig build test-movement

test-glb:
    zig build test-glb

# Analysis and reporting
stats:
    @echo "=== Project Statistics ==="
    @tokei --sort code

lines:
    @echo "=== Code Line Counts ==="
    @find src -name "*.zig" | xargs wc -l | sort -n
    @echo ""
    @find examples -name "*.zig" | xargs wc -l | sort -n

# glTF model analysis
gltf-report MODEL="Box":
    zig run examples/demo_app/test_report.zig -- {{MODEL}}

# Performance benchmarking
bench-build:
    @echo "=== Build Performance ==="
    hyperfine --warmup 2 'zig build demo_app'

bench-run:
    @echo "=== Runtime Performance (5 second samples) ==="
    hyperfine --warmup 1 --max-runs 3 --command-name "demo_app" 'timeout 5s zig build demo_app-run || true'

# Shader validation (requires glslang)
validate-shaders:
    @echo "=== Shader Validation ==="
    @find examples/demo_app/shaders -name "*.vert" -o -name "*.frag" | while read shader; do \
        echo "Checking $$shader..."; \
        glslangValidator "$$shader" && echo "✅ Valid" || echo "❌ Invalid"; \
    done

# Clean build artifacts
clean:
    rm -rf zig-cache zig-out
    @echo "Build artifacts cleaned"

# Development environment validation
doctor:
    @echo "=== Development Environment Check ==="
    @echo "Zig version:"
    @zig version
    @echo ""
    @echo "Available tools:"
    @which glslangValidator > /dev/null && echo "✅ glslangValidator" || echo "❌ glslangValidator (install with: brew install glslang)"
    @which hyperfine > /dev/null && echo "✅ hyperfine" || echo "❌ hyperfine (install with: brew install hyperfine)"
    @which tokei > /dev/null && echo "✅ tokei" || echo "❌ tokei (install with: cargo install tokei)"
    @which watchexec > /dev/null && echo "✅ watchexec" || echo "❌ watchexec (install with: cargo install watchexec-cli)"
    @echo ""
    @echo "Asset directory:"
    @ls -la assets/ | head -5

# Git workflow helpers
commit-prep: fmt check test
    @echo "=== Ready for commit ==="
    @echo "✅ Code formatted"
    @echo "✅ Compilation checked"
    @echo "✅ Tests passed"

# Quick model cycling test
demo-models:
    @echo "=== Testing demo models ==="
    @echo "Starting demo app - use 'n' to cycle through models, 'h' for help"
    just run

# Plan 003 specific - PBR shader development
pbr-dev:
    @echo "=== PBR Shader Development Mode ==="
    watchexec --clear --restart --exts=vert,frag,zig --ignore-paths=zig-cache,zig-out -- bash -c 'just validate-shaders && just run'

# Memory and performance analysis
profile:
    @echo "=== Performance Profile ==="
    @echo "Building with debug info..."
    zig build demo_app -Doptimize=Debug
    @echo "Run with: instruments -t 'Time Profiler' ./zig-out/bin/demo_app"
    @echo "Or use: valgrind --tool=callgrind ./zig-out/bin/demo_app"

# Project maintenance
update-docs: stats
    @echo "=== Updating Documentation ==="
    @echo "Current stats:"
    @just stats
    @echo ""
    @echo "Don't forget to update CHANGELOG.md and CLAUDE.md if needed"

# Debug builds
debug: check
    zig build demo_app -Doptimize=Debug

release: check test
    zig build demo_app -Doptimize=ReleaseFast

# Asset management
check-assets:
    @echo "=== Asset Directory Status ==="
    @find assets -name "*.gltf" -o -name "*.glb" | wc -l | xargs echo "Total models:"
    @du -sh assets/
    @echo ""
    @echo "Recent models:"
    @ls -la assets/ | head -10