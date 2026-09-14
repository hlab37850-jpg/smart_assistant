# PROJECT_SPEC.md

# المساعد الذكي — Smart Assistant

## 1. Project goal

Build a professional Arabic RTL Flutter Android application for managing
customers, current balances, due dates, inventory, imports, backups, and
reports.

The application must be real, usable, and data-driven.

It must not be a visual prototype.

## 2. Current repository

Repository:
https://github.com/hlab37850-jpg/smart_assistant

Technology:
Flutter / Dart / Android

Current package name and Android application ID:
Inspect the repository before changing them.
Do not assume a package name.

## 3. Core principles

- Arabic RTL first.
- Professional and clear user experience.
- Real local persistence.
- No fake data presented as real data.
- No hardcoded shop identity.
- Preserve existing data.
- Avoid unnecessary permissions.
- No local build requirement for the user.
- All Android builds must run through GitHub Actions.

## 4. Main business scope

The application manages:

- Shop settings.
- Customers.
- Current customer balances.
- Due dates and reminders.
- Inventory and remaining stock.
- Product names, quantities, units, and prices where supported.
- Data import and validation.
- Reports.
- Backup and restore.
- Application settings.

## 5. Accounting scope restriction

The application is not a full accounting journal system.

Do not add the following unless explicitly requested:

- Sales invoices.
- Purchase invoices.
- Payment receipts.
- Sales transactions.
- Purchase transactions.
- Journal entries.
- Accounting ledger entries.

Current balances must remain independent and accurate.

Negative balances must be preserved.

## 6. Import requirements

Supported import formats may include:

- PDF.
- Excel.
- CSV.

Before importing:

1. Detect the file type.
2. Extract the data.
3. Show a preview.
4. Validate fields.
5. Detect duplicates.
6. Allow add, update, ignore, or review decisions.
7. Save only after confirmation.

For PDF files:

- Do not rely blindly on raw text order.
- Preserve table structure where possible.
- Preserve Arabic and English text.
- Preserve digits, symbols, decimal values, and units.
- Never reverse Arabic text manually.

## 7. AI assistant

The AI assistant must:

- Explain data using actual stored data.
- Avoid inventing customer balances or inventory quantities.
- Clearly distinguish evidence from assumptions.
- Handle unavailable data honestly.
- Keep API keys outside the repository.
- Use configurable AI settings.

The exact provider and model must be read from the current project
configuration or specification before implementation.

## 8. UI requirements

- Arabic RTL.
- Professional mobile-first layout.
- Clear navigation.
- Consistent typography.
- Accessible contrast.
- Responsive layouts.
- No unnecessary decorative icon cards for customers or products.
- Preserve the approved design direction unless a change is requested.

## 9. Data and persistence

Inspect the existing implementation before changing the data layer.

Use the existing persistence approach where practical.

Do not migrate or delete data without:

- A clear reason.
- A migration plan.
- Validation.
- Backup consideration.

## 10. Quality requirements

A feature is complete only when:

- Its UI exists.
- Its data flow works.
- Its persistence works.
- Its error states work.
- Its loading states work.
- Its empty states work.
- Its validation works.
- Its tests or verification steps pass.
- It works in the cloud build.

## 11. Cloud build requirements

The project must support:

- Flutter dependency installation.
- Static analysis.
- Automated tests.
- Release APK build.
- Optional AAB build.
- Artifact upload.
- Clear failure logs.

The user does not want to build locally.

## 12. Definition of done

A task is complete only when:

- The requested behavior is implemented.
- No known blocking errors remain.
- Tests have been run.
- The Android release build has been run.
- The result is available in GitHub Actions.
- The final report includes evidence.

If a requirement cannot be verified, state that clearly.
