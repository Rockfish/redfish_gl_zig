# Active Plans

## 🔄 Currently Active

- **[001-glb-support-and-demo.md](001-glb-support-and-demo.md)** - GLB format support + interactive demo
  - Phase 1: 📋 GLB Implementation | Phase 2: 📋 Demo App | Phase 3: 📋 Validation Tests
  - **Next**: Start with GLB magic header detection and basic parsing

## 📋 Planned (Priority Order) - Foundation Layer

- **[002-basic-pbr-shaders.md](002-shader-improvements.md)** - Basic PBR rendering and materials
  - Depends on Plan 001 completion
  - Target: 1-2 weeks, focused on essential PBR features

- **[003-basic-animation.md](003-animation-state-machine.md)** - Essential animation and state management
  - Depends on Plans 001-002
  - Target: 1-2 weeks, focused on character movement

- **[004-basic-scene-mgmt.md](004-scene-management.md)** - Multi-model scene support
  - Depends on Plans 001-003
  - Target: 1-2 weeks, focused on scene composition

## ✅ Completed

- **Architecture Refactoring** - Completed 2024-06-24 (commit 6725b17)
  - Separated glTF parsing from rendering components
  - Moved core modules out of gltf/ directory
  - Enhanced CLAUDE.md with project documentation

## ❌ Cancelled/Postponed

- None currently

## Development Philosophy

**Layered Feature Development**: Build horizontal layers of functionality across the engine rather than vertical feature silos. Each plan adds a bounded set of features that work together, keeping the engine functional and demonstrable at each iteration.

**Foundation Layer (Plans 001-004)**: Essential features for a working 3D engine
- GLB support + demo framework
- Basic PBR rendering  
- Essential animation
- Multi-model scenes

**Future Layers**: Advanced features will be selected from backlog after foundation completion.

## Current Focus Summary

**Active**: Plan 001 - GLB Support and Demo App  
**Phase**: 1 (GLB Format Support)  
**Next Task**: Implement GLB magic header detection in asset_loader.zig  
**Target**: Basic GLB loading by end of week  

**Foundation Layer Target**: 6-8 weeks total for Plans 001-004
**Each Plan Target**: 1-2 weeks maximum

**Key Dependencies**: None - can proceed immediately  
**Blockers**: None identified  

## Session Notes

**2024-06-25**: 
- Restructured planning system for iterative, layered development
- Created backlog.md with advanced features moved from original plans
- Simplified Plans 002-004 to focus on essential features only
- Each plan now targets 1-2 weeks with specific, bounded scope
- Foundation layer approach ensures continuous progress and working demos