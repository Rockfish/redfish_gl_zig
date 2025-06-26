# Test Suite

This directory contains the test suite for the redfish_gl_zig 3D graphics engine.

## Structure

```
tests/
├── unit/                    # Unit tests for individual functions
├── integration/             # Integration tests for full workflows  
├── samples/                 # Tests using glTF sample models
├── run_tests.zig           # Test runner
├── test_utils.zig          # Shared test utilities
└── README.md               # This file
```

## Test Categories

### Unit Tests (`unit/`)
Test individual functions and components in isolation:
- GLB parsing functions
- GLTF JSON parsing
- Math library operations
- Error handling

### Integration Tests (`integration/`)
Test complete workflows and component interactions:
- Full GLB loading pipeline
- Full GLTF loading pipeline
- Format comparison (GLB vs GLTF)
- Asset loading and model building

### Sample Model Tests (`samples/`)
Test with real-world glTF sample models:
- Simple models (Box, Triangle)
- Complex models (DamagedHelmet, FlightHelmet)
- Edge cases (Unicode filenames, malformed files)

## Running Tests

### All Tests
```bash
cd tests
zig run run_tests.zig
```

### Individual Tests
```bash
cd tests
zig run integration/glb_loading_test.zig
```

### Specific Test Categories
```bash
# Integration tests only
cd tests/integration
zig run glb_loading_test.zig

# Unit tests only  
cd tests/unit
zig run glb_parsing_test.zig
```

## Test Data

Tests use the glTF 2.0 sample models from:
https://github.com/KhronosGroup/glTF-Sample-Models

Expected location: `/Users/john/Dev/Assets/glTF-Sample-Models/2.0/`

## Adding New Tests

### Unit Test Template
```zig
const std = @import("std");
const testing = std.testing;

test "function_name should do something" {
    // Test implementation
    try testing.expect(condition);
}
```

### Integration Test Template  
```zig
const std = @import("std");
const test_utils = @import("../test_utils.zig");

pub fn main() !void {
    test_utils.printTestHeader("Test Name");
    
    // Test implementation
    
    test_utils.printTestResult(success, "Test description");
    test_utils.printTestFooter();
}
```

## Test Guidelines

1. **Clear Test Names**: Use descriptive names that explain what is being tested
2. **Good Error Messages**: Provide helpful output when tests fail
3. **Isolated Tests**: Each test should be independent and not rely on other tests
4. **Test Data**: Use the shared sample models in `test_utils.zig`
5. **Documentation**: Comment complex test logic and edge cases