---
name: run-tests
description: "Run this project's test suite. Use when the user asks to run tests, verify a change, check if something passes, or before finishing a task. {{FILL: name the test runner}}."
---

# Run tests

<!-- The scaffolder fills the {{...}} from the Project Profile (commands + testing). -->

- All tests: `{{TEST_CMD}}`
- A single file: `{{TEST_ONE_CMD}}`
- First-time setup (if any): `{{TEST_SETUP_CMD}}`

After changing code, run the relevant test file first, then the full suite before declaring done.
A `Stop`-gate hook also blocks finishing while tests fail.
