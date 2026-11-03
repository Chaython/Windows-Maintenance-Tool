# WinUI 3 application plan

## Goal

Add a modern WinUI 3 application as a separate Windows build target while
preserving the existing PowerShell/WPF application, its PS2EXE build, and its
release process. The WinUI 3 app should reuse maintenance operations where
practical rather than reimplementing them.

## Proposed architecture

- **Existing app:** Keep `WMT-GUI.ps1`, `Start_WMT_GUI.bat`, and the current
  PS2EXE workflow as-is unless a separately approved change is needed.
- **New UI:** Build a Windows App SDK / WinUI 3 client in C#. C++ is not the
  preferred starting point because it adds complexity without a clear need.
- **Maintenance worker:** Extract reusable operations from the WPF script into
  a separate PowerShell worker/API boundary. Do not make the WinUI app depend
  on WPF controls, window state, or functions that assume the WPF UI exists.
- **Communication:** Initially, the C# client should invoke the worker as a
  separate process with versioned, structured requests and responses. Define
  progress, cancellation, errors, elevation, and output handling as part of
  that contract.
- **Data and configuration:** Start with WinUI-specific settings. Read existing
  WMT data selectively only where the proof of concept needs it; avoid changing
  existing formats or behavior for WPF users.

## Exclusive app use

- Treat WPF and WinUI 3 as independent apps with no live synchronization.
  Only one frontend may run at a time in the same interactive Windows session.
- Use a shared named Windows mutex, not process-name detection, to acquire
  exclusive ownership before starting frontend work. Reuse the existing WPF
  single-instance mechanism, with a small startup-handling adjustment where
  needed; leave its build process unchanged.
- If the other frontend is running, show: "Another version of Windows
  Maintenance Tool is running. Close it before opening this version." Then
  exit without starting maintenance work.
- A frontend hidden in the tray still owns the mutex. Release ownership on
  exit; Windows also releases it if the owning process crashes.
- Worker processes started by the active app must remain permitted and must
  not be mistaken for another frontend. Define worker shutdown behavior so
  closing a frontend cannot leave conflicting work running.

## Build, docs, and support

- Keep the existing PowerShell/PS2EXE build and its documentation separate and
  unchanged.
- Give WinUI 3 its own project, build, tests, documentation, and release target.
- Defer the WinUI packaging/distribution choice until the proof of concept has
  validated the app model, elevation, and update behavior.
- Target Windows 10 22H2 and currently supported Windows 11 releases. Select
  Windows App SDK and .NET versions compatible with both before implementation.
- Provide fallbacks for Windows 11-only visuals and APIs. Document application
  compatibility separately from Microsoft's OS servicing status; compatibility
  does not imply that a Windows installation still receives security updates.

## Suggested delivery stages

1. Inventory reusable operations and identify WPF/UI coupling.
2. Define a small worker contract and extract one low-risk operation.
3. Create a proof-of-concept WinUI 3 shell that requests a read-only
   system-health summary and validate worker invocation, progress, errors, and
   elevation. Test mutual exclusion in both launch orders, simultaneous
   launches, tray mode, crash recovery, and permitted worker startup. Validate
   the proof of concept on both Windows 10 22H2 and Windows 11.
4. Add representative workflows incrementally, with tests for both the worker
   contract and UI integration.
5. Evaluate feature parity and release readiness without changing the existing
   app's release path.

## Main risks

- Maintenance functions may depend on WPF state or global script variables,
  making extraction larger than expected.
- Process invocation needs careful handling of elevation, cancellation,
  progress, and structured output.
- Shared settings or output paths can introduce compatibility and data-loss
  risks if their existing behavior is not preserved.
- The WinUI target needs an independently maintained build and test setup.
- Windows 10 compatibility requires ongoing cross-version testing and guarding
  newer OS APIs; SDK and runtime upgrades must preserve the chosen baseline.

## Open decisions

- Which additional WMT workflows should follow the proof of concept?
