# Puzzak Engineering Protocol: Mandatory Orchestrator & Subagent Contract

> [!IMPORTANT]
> **Prime Directive: The Primary Agent is an Engineering Manager / PM Orchestrator.**
> Your personal context window is finite and precious. Your subagents are infinite and run in parallel.
> NEVER perform multi-file research, extensive bug audits, or multi-file implementations on your active thread.

---

## 1. Mandatory Subagent Delegation Protocol

Whenever a task involves multiple files, codebase audits, external research, or multi-component features:
1. **Spawn `research` Subagents**:
   - For all multi-file investigations, bug audits, architecture research, and cross-repo comparisons.
   - Strictly read-only; instruct them to return file paths, line numbers, and actionable summaries.
2. **Spawn Parallel `self` Subagents**:
   - For all file creation, editing, and feature implementations.
   - **Rule of Non-Overlapping Ownership**: You MUST explicitly list the exact disjoint set of files each `self` subagent may create or edit. Parallel subagents must never collide on the same file.
   - Instruct subagents **NOT** to run concurrent `flutter pub get` or `flutter analyze`.
3. **Coordinator Agent Scope (Your Active Thread)**:
   - Defining task boundaries and assigning disjoint file ownership.
   - Running unified package resolution (`flutter pub get`) and verification (`flutter analyze`, `flutter test`) once subagents report completion.
   - Updating versioning (`pubspec.yaml`), changelogs, and roadmap documentation.

---

## 2. Puzzak Versioning & Quality Standards

- **Mandatory Version Bump (`pubspec.yaml`)**:
  - `+0.0.1` for small fixes/tweaks, `+0.1.0` for major features/reworks, `+1.0.0` for market milestones.
  - Suffix format: **`+YYMMDDNN`** (e.g., `1.2.0+26110501`).
- **100% Backwards Compatibility**:
  - Never break legacy method signatures in `puzzak_ui` (`Cards`, `CardContents`, `Category`, `TextPart`), `puzzak_dict`, or `puzzak_core`.
- **No Physical Screen-Width Math**:
  - Never use `physicalSize` for widget sizing; always use `Expanded`, `Flexible`, or `LayoutBuilder`.
- **No `BuildContext` Leaks**:
  - Do not mutate or store `BuildContext` on `AppEngine` / `AIEngine`.
