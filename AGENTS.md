# AGENTS.md

## Project identity

This repository contains a real Flutter Android application named:
Smart Assistant / المساعد الذكي.

The project is not a mockup. All requested features must be implemented as
real, working functionality.

## Language and UI

- The primary interface is Arabic RTL.
- Preserve Arabic text direction and Unicode correctness.
- Do not reverse Arabic strings manually.
- Do not manually join Arabic characters or mutate Unicode code points.
- Use Flutter's native RTL and text layout support.
- Use the existing project design direction unless the specification requires a change.

## Before making changes

1. Inspect the complete repository structure.
2. Read README.md, PROJECT_SPEC.md, DESIGN_SPEC.txt, and pubspec.yaml.
3. Inspect the existing Dart source files and tests.
4. Identify the current Flutter, Dart, Android, Gradle, AGP, and Java requirements.
5. Check whether a requested feature already exists before creating a duplicate.
6. Explain the implementation plan before making broad changes.

## Implementation rules

- Build real functionality, not placeholder screens.
- Do not replace working features with mock data.
- Do not hardcode shop identity or customer data.
- Preserve existing user data and compatibility where possible.
- Do not delete existing features without a documented reason.
- Keep the project maintainable and organized.
- Avoid unnecessary dependency changes.
- Never commit API keys, passwords, signing keys, or other secrets.
- Use secure configuration for external AI services.
- Prefer narrow permissions and safe file access.

## Data rules

- Preserve negative customer balances.
- Do not introduce sales, purchases, payments, invoices, receipts, or journal
  entries unless explicitly required by the current specification.
- Current balances and inventory quantities must remain accurate.
- Imports must validate data before writing it.
- PDF extraction must not assume that raw text order represents visual order.
- Preserve Arabic and English digits, symbols, decimal values, and units.

## Testing and validation

After every meaningful implementation stage:

1. Run formatting checks where appropriate.
2. Run flutter analyze.
3. Run flutter test.
4. Run the relevant build command.
5. Inspect the complete failure log if anything fails.
6. Fix the root cause and rerun the failed check.
7. Do not claim success without actual command output.

## Git workflow

- Work on a dedicated branch.
- Keep commits focused and descriptive.
- Do not force-push.
- Do not delete the repository or its data.
- Prefer a Pull Request for review.
- Do not merge automatically unless explicitly authorized.

## Final report

Always report:

- What was implemented.
- Files created or modified.
- Tests executed and their results.
- Build command and result.
- Remaining problems.
- Commit or Pull Request URL.
- GitHub Actions workflow URL.
- APK/AAB artifact URL if available.
- Whether success was verified or only inferred.

Never describe an unverified build as successful.
