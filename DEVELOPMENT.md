# Development Workflow Guide

## Quick Start Commands

### Just Recipes (Recommended)
```bash
# Show all available commands
just

# Start development with auto-rebuild
just dev

# Quick build and run
just run

# Run tests
just test

# Format code
just fmt

# Check compilation without building
just check

# PBR shader development (Plan 003)
just pbr-dev

# Project statistics
just stats

# Performance benchmarks
just bench-build
```

### Direct Commands
```bash
# Build and run
zig build demo_app-run

# Just build
zig build demo_app

# Check compilation
zig build check

# Run tests
zig build test-movement
zig build test-glb
```

### Development Watchers
```bash
# Auto-rebuild and run on any .zig file change
./scripts/watch-dev.sh

# Shader development with validation (Plan 003)
./scripts/watch-shaders.sh

# Build-only watcher (fast feedback)
./scripts/watch-build.sh
```

## Common Workflows

### 🎮 Normal Development
```bash
just dev
# Or: ./scripts/watch-dev.sh
```
- Watches all `.zig` files
- Auto-rebuilds and runs demo on changes
- Perfect for testing new features

### 🎨 Shader Development (Plan 003)
```bash
just pbr-dev
# Or: ./scripts/watch-shaders.sh
```
- Watches shader files (`.vert`, `.frag`) 
- Validates shaders with `glslangValidator`
- Auto-rebuilds and runs demo
- Ideal for PBR shader iteration

### ⚡ Fast Compilation Feedback
```bash
./scripts/watch-build.sh
```
- Only compiles, doesn't run
- Fastest feedback for syntax errors
- Good for refactoring sessions

### 🧪 Testing Before Commit
```bash
just commit-prep
```
- Formats code
- Checks compilation
- Runs all tests
- Ensures clean commit state

## Performance Analysis

### Build Performance
```bash
just bench-build
```
Uses `hyperfine` to benchmark build times.

### Runtime Performance  
```bash
just bench-run
```
Short runtime benchmarks (5-second samples).

### Code Statistics
```bash
just stats        # Overall project stats
just lines        # Line counts by file
```

## Shader Development (Plan 003)

### Validate Shaders
```bash
just validate-shaders
```
Checks all `.vert` and `.frag` files with `glslangValidator`.

### Shader Locations
- **Vertex shaders**: `examples/demo_app/shaders/*.vert`
- **Fragment shaders**: `examples/demo_app/shaders/*.frag`

## Model Analysis

### glTF Inspection
```bash
just gltf-report                    # Default model (Box)
just gltf-report MODEL=Fox          # Specific model
```

### Demo Model Testing
```bash
just demo-models
```
Starts demo app with instructions for model cycling.

## Environment Setup

### Check Development Tools
```bash
just doctor
```
Validates that all required tools are installed.

### Required Tools
```bash
# Essential for shader development
brew install glslang

# Performance benchmarking  
brew install hyperfine

# Code statistics
cargo install tokei

# File watching
cargo install watchexec-cli

# Command runner (for just recipes)
brew install just
```

## Asset Management

### Check Assets
```bash
just check-assets
```
Shows model counts, disk usage, and recent files.

### Asset Directory
- **Location**: `assets/`
- **Formats**: `.gltf`, `.glb`
- **Current models**: 15 curated demo models

## Build Configurations

### Development (default)
```bash
just build
```

### Debug Build
```bash
just debug
```
Includes debug symbols for profiling.

### Release Build
```bash
just release
```
Optimized for performance testing.

## Tips

1. **Use `just dev` for most development** - provides the best workflow
2. **Use `just pbr-dev` for shader work** - includes validation
3. **Run `just doctor` after installing new tools** - verifies setup
4. **Use `just commit-prep` before committing** - ensures quality
5. **Model cycling in demo**: Press `n`/`b` to cycle, `h` for help

## Keyboard Shortcuts in Demo

### Model Navigation
- **N** - Next model
- **B** - Previous model  
- **F** - Frame to fit
- **R** - Reset camera

### Animation
- **0** - Reset animation
- **=** - Next animation
- **-** - Previous animation

### Display
- **H** - Toggle help
- **C** - Toggle camera info

See `examples/demo_app/state.zig` for complete control reference.