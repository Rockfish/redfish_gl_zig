# Project Plan System

This directory contains structured project plans following a layered development approach to maintain continuity and ensure steady progress across development sessions.

## Development Philosophy

**Layered Feature Development**: Build horizontal layers of functionality across the engine rather than diving deep into vertical feature silos. This approach ensures:
- Engine remains functional and demonstrable after each iteration
- Features build incrementally without long development periods
- Continuous visible progress and regular milestones
- Risk reduction through shorter development cycles

## File Organization

- `NNN-descriptive-title.md` - Individual plan files (numbered for ordering)
- `active-plans.md` - Index of current iteration plans with status
- `backlog.md` - Future features organized by development layers
- `README.md` - This file (how to use the system)
- `completed/` - Archive for finished plans (future)

## Development Layers

### Foundation Layer (Current - Plans 001-005)
Essential features for a working 3D engine:
- **Plan 001**: GLB Format Support ✅ COMPLETED
- **Plan 002**: Demo Application 🔄 ACTIVE
- **Plan 003**: Basic PBR Shaders
- **Plan 004**: Essential Animation System  
- **Plan 005**: Multi-Model Scene Management

**Target**: 6-8 weeks total, 1-2 weeks per plan

### Future Layers
Advanced features selected from backlog after foundation completion:
- **Layer 2**: Advanced rendering, complex animation, optimization
- **Layer 3**: Engine integration, tools, polish

## Plan File Format

Each plan follows a focused template:
- **Header**: Status, priority, target duration (1-2 weeks)
- **Overview**: What and why (bounded scope)
- **Prerequisites**: Dependencies from previous plans
- **Phases**: 1-2 phases maximum with specific tasks
- **Success Criteria**: Measurable outcomes for the iteration
- **Scope Limitations**: What's explicitly NOT included (moved to backlog)
- **Notes & Decisions**: Date-stamped progress log

## Workflow

### Starting a Session
1. Check `active-plans.md` for current iteration focus
2. Open the active plan file to see next tasks  
3. Review recent notes for context and decisions

### During Development
1. Check off completed tasks: `- [x]`
2. Add discoveries and decisions with dates
3. Update task descriptions if scope changes
4. Stay focused on plan's bounded scope

### Ending a Session
1. Update progress in plan file with session notes
2. Update `active-plans.md` if status changed
3. Add any new discoveries to backlog if out of scope

### Completing a Plan
1. Mark all success criteria as met
2. Update active-plans.md status to completed
3. Review backlog for next iteration planning
4. Archive completed plan (future: move to completed/)

## Backlog Management

The `backlog.md` file organizes future features by development layers:
- Features are grouped into logical clusters
- Each cluster targets 1-2 weeks of development
- Features build naturally on foundation layer
- Regular review and reprioritization based on actual needs

### Next Iteration Selection
After completing foundation layer:
1. Review current engine capabilities
2. Evaluate backlog clusters for next priorities
3. Select 2-3 clusters for next iteration
4. Create new focused plan files for selected features

## Status Indicators

- 🔄 **Active** - Currently being worked on (one plan only)
- 📋 **Planned** - Ready to start when prerequisites are met
- ✅ **Complete** - All success criteria met
- ❌ **Cancelled** - No longer relevant or superseded

## Best Practices

- **One Active Plan** - Focus on single plan to maintain momentum
- **Bounded Scope** - Each plan adds specific, limited features
- **Short Iterations** - 1-2 weeks maximum per plan
- **Working Demos** - Engine functional after each plan
- **Decision Log** - Record architectural choices and reasoning
- **Scope Discipline** - Move out-of-scope items to backlog