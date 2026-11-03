# Decisions

## Scope and applicability

This log records durable operating-practice and compatibility decisions for the OmniWM Computer Use skill in this repository. It applies to the skill's automation guidance, setup verifier, and bundled focus helper behavior. It excludes OmniWM application behavior, Chrome user settings, company project work, and task-specific evidence beyond what supports these decisions.

## 2026-11-02 — Prefer native accessibility for background Chrome control

**Decision:** Use Chrome's app-local accessibility interface as the primary background-control path where the target exposes the needed controls. Keep extension DOM interaction as a fallback and inspect state before retrying after intermittent `Detached` errors, since an action may have succeeded despite the error. Do not pre-focus, reposition, or use global input for this path. Treat the focus guard as a backup, not as the execution strategy or a guarantee of hard isolation.

**Context and rationale:** In the verified session, app-local accessibility read Chrome state and successfully clicked an index in the task's own tab, selected a radio option, and set a text area's value while Chrome was unfocused and offscreen. Codex remained the focused app and window frames did not change. Extension DOM fill, dropdown, and checkbox actions also succeeded, but intermittent detached errors made state inspection necessary before retrying.

**Consequences and limits:** These observations establish only the tested controls and session. They do not establish support for arbitrary coordinates, custom widgets, all background interactions, or foreground focus isolation.

## 2026-11-02 — Accept verified OmniWM protocol variants with capability checks

**Decision:** The setup verifier may accept established protocol 10 and the tested OmniWM 0.7.6 protocol 19 only when the expected schema and capabilities are present and the bundled CLI matches. Keep default verification read-only. Perform actual focus capture and restoration only in explicit `--check-restore` mode.

**Context and rationale:** The previous exact protocol-10 gate rejected a live interface whose query and guard capabilities were compatible. Verification must itself preserve the user's working focus, so routine setup checks must not exercise focus changes.

**Consequences and follow-up:** Validate both protocol paths with read-only live checks and fixtures. Foreground guard interception was not tested or approved in this session; the verifier must not imply that it was.

**Validation clarification (2026-11-02):** Follow-up completed with fixtures for protocols 10 and 19, plus a live read-only protocol-19 check on OmniWM 0.7.6; the default verifier passed live. Protocol 10 was not exercised live, and deliberate focus-guard interception was not exercised. Independent review is underway.

**Review clarification (2026-11-02):** Independent review found no actionable issues. Live protocol-19 and default read-only verifier checks passed; protocol 10 was checked against its documented source contract and fixtures, not live.

## 2026-11-02 — Keep remote debugging outside the default dependency path

**Decision:** Treat missing `DevToolsActivePort` as a separate disabled remote-debugging dependency. Do not enable remote debugging as a prerequisite for the verified native accessibility path.

**Context and rationale:** The native path worked without remote-debugging access. Enabling it would expand access without being needed for the demonstrated workflow.

**Consequences and limits:** This does not decide whether remote debugging may be used for a separately authorized workflow; it is not a prerequisite for the default path.

## 2026-11-02 — Make focus guarding a one-shot decision

**Decision:** The focus guard makes at most one decision. It intercepts an expected app selected by bundle ID or name, or a newly created window when no app selector is supplied. If an unrelated pre-existing window gains focus, yield and disarm. Guard cleanup never restores focus; explicit focus capture and restoration remains confined to verifier `--check-restore` mode.

**Clarification (2026-11-02):** Helper capture and restore commands remain available for explicitly authorized bounded foreground actions; only the verifier's own restore exercise is gated by `--check-restore`.

**Context and rationale:** A continuously restoring guard could fight the user's intentional app switches, and cleanup could refocus a stale protected window.

**Consequences and limits:** A deliberate switch to the expected app remains ambiguous. The guard does not provide hard isolation or eliminate focus races. Tests cover the one-shot behavior.
