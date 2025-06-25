# Project Plan System

This directory contains structured project plans to maintain continuity across development sessions.

## File Organization

- `NNN-descriptive-title.md` - Individual plan files (numbered for ordering)
- `active-plans.md` - Index of all plans with current status
- `README.md` - This file (how to use the system)

## Plan File Format

Each plan file follows a standard template:
- **Header**: Status, priority, dates
- **Overview**: What and why
- **Prerequisites**: Dependencies that must be completed first
- **Phases**: Organized groups of tasks with checkboxes
- **Success Criteria**: Measurable outcomes
- **Notes & Decisions**: Date-stamped progress log
- **Related Files**: Code files involved

## Workflow

### Starting a Session
1. Check `active-plans.md` for current focus
2. Open the active plan file to see next tasks
3. Review recent notes for context

### During Development
1. Check off completed tasks: `- [x]`
2. Add discoveries and decisions with dates
3. Update task descriptions if scope changes

### Ending a Session
1. Update progress in plan file
2. Add session summary with date
3. Update `active-plans.md` if status changed

## Status Indicators

- 🔄 **Active** - Currently being worked on
- 📋 **Planned** - Ready to start when prerequisites are met
- ✅ **Complete** - All success criteria met
- ❌ **Cancelled** - No longer relevant or superseded

## Best Practices

- **One Active Plan** - Focus on single plan to avoid scattered effort
- **Specific Tasks** - Actionable items, not vague goals
- **Regular Updates** - Keep plans current with actual progress
- **Decision Log** - Record why choices were made
- **File References** - Link to specific code locations