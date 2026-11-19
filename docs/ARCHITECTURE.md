# Enrollment Bundle Studio: Architecture

Status: all four phases implemented. Phase 4 builds unsigned flat packages with pkgbuild, verifies them with pkgutil, and records reports and history (see PACKAGING_AND_DEPLOYMENT.md). Package signing was dropped by decision; earlier sections that mention productbuild, signing identities or spctl describe the original plan. Phase 3 added the generated Bash 3.2 framework (see FRAMEWORK.md), export, simulation and live swiftDialog preview. Phase 2 added script import and inspection, the task planner and dependency graph, the validation engine, configuration export and import, schema migration (schema 2) and the command runner. Phases 3 and 4 are designed here.

## 1. Final architecture

The application is a SwiftUI document-based app targeting macOS 13+, built with MVVM.

**Document layer.** `EnrollmentProjectDocument` is a `FileDocument` backed by a directory `FileWrapper`. SwiftUI's `DocumentGroup` therefore provides New, Open, Open Recent, Save, Save As, Duplicate, Rename, Revert, autosave, versions and undo without custom code. The document holds two things: `project` (the decoded `project.json`) and `assets` (the bytes of every file in the managed folders `Branding/`, `Icons/` and `Scripts/`, keyed by relative path). Writing starts from the existing file wrapper and only rewrites `project.json` and the managed folders, so `Templates/`, `Generated/` and `Builds/` are never touched by a save.

**Model layer** (`Models/`, Foundation only). Plain `Codable` value types: `EnrollmentProject`, `ProjectSettings`, `Branding`, `ApplicationGroup`, `ApplicationItem`, `ScriptItem`, `EnrollmentTask`, and shared building blocks (`TaskExecutionOptions`, `TaskMessages`, `IconSource`, `TaskCheck`, `TaskStatus`). Editing operations live in `EnrollmentProject+Editing.swift` so they are unit-testable without UI.

**Service layer** (`Services/`, `Catalog/`, `Preview/`). Stateless, testable logic: project coding and schema checks, field validation, filename sanitising, relative-path guarding, image import, completion and unlock rules, preview state building, the application catalogue. Phase 2 adds the validation engine, dependency graph, script inspector and migrator; Phase 3 the framework generator and dialog controller; Phase 4 the command runner, package builder, signing identity reader and report writer.

**View-model layer** (`ViewModels/`). `WorkspaceViewModel` is a `@MainActor ObservableObject` owned per window with `@StateObject`. It holds UI state that must outlive a single page (collapsed groups, preview scenario and simulated statuses, alerts) plus one-shot *requests* from menu commands. Project data deliberately stays in the document binding so dirty tracking and undo remain automatic.

State-ownership rules (they keep SwiftUI's "Publishing changes from within view updates" warning away): selection, presentation flags and filters are `@State` in the view that owns them (the sidebar selection lives in `ContentView`; sidebar rows are buttons that set it directly, because `List(selection:)` and `NavigationLink(value:)` did not reliably update it on macOS 26; menu commands navigate through `workspace.navigate(to:)`, handled by ContentView in `.task(id:)`, because a focused binding can be stale while a menu is tracked); menu commands call `workspace.request(_:)`, and the target view handles it in `.task(id:)`, which runs after the view update; every published view-model property publishes only when its value actually changes.

**View layer** (`Views/`). `NavigationSplitView` with a sidebar of ten sections. Every editor receives `Binding<EnrollmentProjectDocument>` plus the workspace. Multi-step edits (import + reference change, remove + asset cleanup) are applied to a local copy and assigned once, so they are a single undo step.

**File panels.** All open and save panels use `NSOpenPanel` and `NSSavePanel` through `FilePanels`, attached as sheets to the key window. SwiftUI's `fileImporter` and `fileExporter` are not used, because several of them in one window can silently fail to appear.

**Document binding.** `DocumentGroup` passes a binding that skips writes of an unchanged value (`skippingEqualWrites()`), so controls writing back the current value never publish during a view update or mark the document edited.

**Menu-based controls.** Popup and segmented pickers, toggles and pickers inside menus, and the color well use `deferringWrites()`, which applies their change one run-loop turn later. On macOS 26 AppKit can deliver a menu choice while SwiftUI is updating views; writing then would publish inside the update. Text fields write immediately.

**External tools** (Phase 3 and 4). All command execution goes through one `CommandRunning` protocol implemented with `Process`, an explicit `executableURL` and an arguments array. An allowlist restricts executables to `/usr/bin/pkgbuild`, `/usr/bin/productbuild`, `/usr/sbin/pkgutil`, `/usr/sbin/spctl`, `/usr/bin/codesign`, `/usr/bin/security`, the configured swiftDialog binary, and an optional local ShellCheck. Nothing uses `/bin/sh -c`. Tests inject a mock runner.

**Launch sequence.** `App/SplashWindowController.swift` shows `SplashImage` (asset catalogue) at 800×450, centred in the usable area of the main screen (menu bar and Dock excluded). It stays 2.5 seconds, then fades out (no fade with Reduce Motion). `App/MainWindowHold.swift` keeps document windows invisible and inert until the splash is gone; then a new project opens. If the image is missing, no splash is shown and the project opens right away. There is no sign-in at launch: `App/AuthSession.swift` signs in through the browser only when Upload to Intune needs a token, using the tenant and client IDs the administrator entered in Settings (`IntuneConnectionStore` in `Services/Intune/IntuneSupport.swift`, kept in user preferences, never in a project). Closing the last open project starts a new untitled project automatically (`AppDelegate.windowWillClose`); quitting the app does not.

## 2. Xcode project and file structure

Final layout (phase that adds each part in brackets):

```
EnrollmentBundleStudio.xcodeproj         Xcode 16+ project, synchronized folders, shared scheme
Config/
  Info.plist                             document type and exported UTI
  EnrollmentBundleStudio.entitlements    no sandbox, documented
EnrollmentBundleStudio/
  App/            EnrollmentBundleStudioApp, AppInfo, StudioCommands                 [1]
  Models/         project, settings, branding, groups, apps, tasks, statuses          [1]
                  ProjectMigrator, ConfigurationArchive                               [2]
  Document/       EnrollmentProjectDocument, ProjectLayout, UTType                    [1]
  Catalog/        ApplicationCatalog                                                  [1]
  Services/       coding, validators, sanitizer, path guard, image import,
                  completion logic, device info                                       [1]
                  ValidationEngine, DependencyGraph, ScriptInspector, Hashing         [2]
                  FrameworkGenerator, DialogConfigBuilder, DialogCommandWriter        [3]
                  CommandRunner, SigningIdentityReader, PackageBuilder,
                  PackageVerifier, BuildReportWriter, BuildHistoryStore               [4]
  Preview/        PreviewBuilder                                                      [1]
                  LiveDialogPreviewController, SimulationEngine                       [3]
  Resources/Templates/  Bash templates for the generated framework                    [3]
  ViewModels/     WorkspaceViewModel, SidebarSection                                  [1]
  Views/          Overview, Branding, Applications, Preview, Settings, components     [1]
                  Scripts, Execution, Validation                                      [2]
                  Live preview and simulation controls                                [3]
                  Package Builder, Build History                                      [4]
EnrollmentBundleStudioTests/                                                          [1-4]
SampleProjects/Contoso.enrollmentproject                                              [1]
docs/                                                                                 [1-4]
```

The project uses Xcode 16 file-system-synchronized groups (`objectVersion = 77`): any Swift file added under `EnrollmentBundleStudio/` or `EnrollmentBundleStudioTests/` is compiled automatically, so later phases add files without editing `project.pbxproj`. `Info.plist` and the entitlements live in `Config/`, outside the synchronized folder, so they are not copied as resources.

## 3. Core data model

```
EnrollmentProject
  schemaVersion, applicationVersion, projectVersion, id, createdAt, modifiedAt
  settings: ProjectSettings          identity, package, device paths, window, timing, strategies, swiftDialog
  branding: Branding                 title, messages, buttons, logo/banner paths, accent, infobox, support
  applicationGroups: [ApplicationGroup]
      name, symbolName, isRequired, displayBehavior
      applications: [ApplicationItem]
          taskIdentifier, catalogID?, displayName, applicationPath, bundleIdentifier,
          processName, icon: IconSource, detection: TaskCheck, installStrategy,
          isEnabled, execution: TaskExecutionOptions
  scripts: [ScriptItem]              relativePath, sha256, interpreter, successExitCodes, execution
  systemTasks: [EnrollmentTask]      Intune sync, wait conditions, final validation
```

`TaskExecutionOptions` is shared by every task source: required, visible, context (root or console user), timeout, retries, dependencies (task identifiers), execution order, parallel group, allow-skip, allow-rerun, and five status messages. Apps and scripts carry their own options, so the Phase 2 planner derives one flat `[EnrollmentTask]` plan from apps, scripts and system tasks; the generated `tasks.json` is that plan.

Task identifiers are stable, readable slugs (`app.microsoft-defender`, `script.configure-dock`, `system.final-validation`) used for dependencies, state files and preview overrides. UUIDs identify items inside the editor only.

`TaskStatus`: pending, waiting, running, complete, completeWithWarnings, skipped, failed, timedOut. A required task is acceptable when it is complete, complete with warnings, or skipped where `allowSkip` is set. `CompletionEvaluator` implements unlock and outcome rules once; the static preview uses it now, the simulation uses it in Phase 3, and the Bash framework implements the same table.

## 4. Security decisions

- Everything stays local. No network calls, no telemetry, no accounts. The catalogue describes detection only and never downloads software.
- Imported files are copied into the project after validation (signature-based image detection, ImageIO decode, 10 MB limit, regular files only). Scripts (Phase 2) are hashed with SHA-256 and inspected as text; they are never executed during import, editing, preview or simulation.
- Every relative path read from `project.json` or an imported configuration passes `RelativePathValidator`: no absolute paths, no `~`, no `.` or `..` components, no backslashes or control characters, and the first component must be an allowed project folder. Unsafe references are removed on open and reported.
- File names derived from user text go through `FilenameSanitizer` (ASCII letters, digits, `.`, `_`, `-`; accents folded; separators trimmed).
- A project with a newer schema opens read-only and refuses to save, so it is never overwritten.
- Destructive edits (remove group, remove application) ask for confirmation and are undoable. Overwriting exported folders or packages (Phase 3/4) always asks first.
- No credentials are stored or requested by the app. Signing uses identities already in the login keychain by SHA-1 hash; any keychain access prompt comes from macOS, not from a custom dialog.
- Building a package never needs root: `pkgbuild --ownership recommended` writes root:wheel ownership into the payload from an ordinary user staging folder. If a future feature truly needs privilege it will explain why at the point of action and use system authorization, never AppleScript `with administrator privileges`.
- The app never removes quarantine attributes, never changes Gatekeeper, and never installs swiftDialog or applications.

## 5. App Sandbox decision

**Decision: App Sandbox off, Hardened Runtime on (Release), Developer ID signing and notarization, internal distribution through Intune.**

Reasons: Phase 4 runs `pkgbuild`, `productbuild`, `pkgutil`, `spctl` and `security` as child processes. Children of a sandboxed app inherit its sandbox, so they cannot read the staging folder freely, cannot reach signing identities in the login keychain reliably, and cannot write packages outside the container without per-path bookmarks passed through. The live preview launches `/usr/local/bin/dialog`, which also misbehaves when sandboxed. The Mac App Store is not a target.

Mitigations that keep the app well-behaved without a sandbox: file access is still user-driven through open and save panels; no paths outside the chosen project, output folder and temporary directories are written; command execution is allowlisted; Hardened Runtime is enabled for Release so the app can be notarized. Debug builds leave Hardened Runtime off so the unit-test bundle can be injected into the ad-hoc-signed host app.

If a sandboxed variant is ever required, the seams are already in place: file access goes through panels (add security-scoped bookmarks for the output folder), and the package builder would move into a non-sandboxed XPC helper or a signed command-line companion.

## 6. Package-building design (Phase 4)

1. **Validate.** The validation engine must report no errors.
2. **Generate.** The framework generator writes the enrollment framework into a fresh staging folder created with `FileManager.url(for: .itemReplacementDirectory, ...)` on the output volume. Layout:
   - payload: `<installLocation>/` with `enrollment.sh`, `uninstall.sh`, `VERSION`, `lib/`, `tasks/`, `config/`, `icons/`, `scripts/`; and `/Library/LaunchDaemons/<bundleIdentifier>.plist`.
   - scripts: `preinstall` (stops a running older enrollment safely) and `postinstall` (sets permissions, bootstraps the LaunchDaemon with `launchctl bootstrap system`).
3. **Build component package.** `/usr/bin/pkgbuild --root <payload> --scripts <scripts> --identifier <packageIdentifier> --version <packageVersion> --install-location / --ownership recommended <component.pkg>`.
4. **Build product archive.** `/usr/bin/productbuild --package <component.pkg> [--sign <identity hash> --timestamp] <EnrollmentBundle-<version>.pkg>`.
5. **Verify.** `pkgutil --check-signature`, `pkgutil --payload-files` for the inventory, `spctl --assess --type install -vv` for Gatekeeper status, SHA-256 computed in-app with CryptoKit.
6. **Report.** Write `<name>-<version>-build-report.txt` beside the package and record the build in history.

Overwriting an existing package or report requires confirmation. Staging folders are removed after the build, also on failure or cancellation.

Why a LaunchDaemon: with Automated Device Enrollment, Intune can install the package before anyone has logged in. The postinstall therefore only installs and starts a daemon; the daemon's `enrollment.sh` waits (with a timeout) for a console user and for swiftDialog, then shows the dialog. This also gives restart and logout resilience.

Signing identities are read with `/usr/bin/security find-identity -v` and filtered to Installer identities (`Developer ID Installer:`). The app never preselects an identity.

## 7. swiftDialog preview design

**Static preview (Phase 1, done).** A native SwiftUI drawing of the dialog: banner, title, logo or completion icon, information box, message, task list with status icons and texts, progress, and the completion button with its lock state. It is built from `PreviewBuilder.makeState`, which applies a scenario, per-item simulated statuses, hidden-task handling, group summary rows, final-validation dependency and the unlock rules. Placeholders resolve with sample values or values from this Mac (the serial number is never read). It needs no swiftDialog and runs nothing.

**Live preview (Phase 3).** When swiftDialog exists at the configured path and `dialog --version` meets the minimum:
1. Create a private temporary folder. Write `dialog.json` produced by the same `DialogConfigBuilder` that the generator uses, plus copies of the icons, and an empty command file.
2. Launch swiftDialog with `Process` as the current user: `--jsonfile <dialog.json> --commandfile <commandfile>`.
3. The app writes simulated updates to the command file (list item status and status text, progress, message, button enable), using the same command vocabulary as the generated `lib/dialog.sh`, so the preview exercises the real protocol without running any enrollment script.
4. Stop terminates the process; closing the window, closing the document or quitting also terminates it and deletes the temporary folder.

If swiftDialog is missing or too old, the Preview page explains that only the static preview is available. It never installs swiftDialog.

## 8. Phased implementation plan

**Phase 1 (delivered).** Xcode project; app shell with `DocumentGroup`, sidebar navigation, menu commands and shortcuts; complete Codable data model; package-directory document handling with asset copying and preservation of unmanaged folders; read-only handling of newer schemas; Overview, Branding (placeholders, images, accent color, infobox, support), Applications (catalogue, custom apps, groups with reorder, move, collapse, required groups, display behavior), app-wide runtime Settings (own window from the app menu: Settings…, ⌘,; Save stores the defaults for new projects and writes them into the frontmost project); built-in catalogue; static preview with scenarios, simulated statuses, hidden tasks and unlock logic; sample project; unit tests.

**Phase 2 (delivered).** Script import (copy, SHA-256, shebang, executable bit, Bash 3.2 construct warnings, risky pattern warnings such as `sudo` and unauthenticated downloads, optional local ShellCheck); Scripts and Execution editors; task planner; dependency graph with cycle, missing, disabled and order checks; validation engine and Validation page; configuration export and import with hashes and path checks; schema migrator with backup and summary.

**Phase 3 (delivered).** Bash 3.2 framework templates and generator (`enrollment.sh`, `lib/*.sh`, `tasks/*.sh`, `config/*`); shared swiftDialog command-file library; per-task timeouts, controlled parallelism, PID tracking, locking with stale-lock detection, TERM and INT handling, state and resume; `--dry-run`, `--preview`, `--force`, `--help`; export of generated files; simulation mode; live swiftDialog preview.

**Phase 4 (delivered, without signing).** Command runner; package builder; signing identity reader; package verification; build reports; build history; internal distribution guide.

### Generated scripts and the scripting standard

Phase 3 templates follow common endpoint scripting rules where they are stricter than or extend this specification: `#!/bin/bash`, Bash 3.2, explicit `PATH`, root check, `set -u` without `set -e`, `mktemp` with an EXIT trap, `log` and `log_error` behaving as specified, console user detection with `scutil`, `launchctl asuser ... sudo -u` for user context, a final one-line `intune_result` in the form `STATUS: message | key=value`, a `--preview` switch in addition to `--dry-run`, swiftDialog precondition checks against a `dialog_min_version`, and the optional overlay icon passed with `--overlayicon` (missing file logged, not fatal). Log files are created with mode 644 so the logged-in user can read them. No console user means the dialog is skipped and non-disruptive detection continues.

## 9. Technical risks

1. **Not compiled in the authoring environment.** Phase 1 was reviewed by hand and structurally checked, but no Swift compiler was available where it was written. Expect to build once and report any compiler message; fixes will be delivered as versioned files.
2. **Xcode version.** Synchronized folders require Xcode 16 or later.
3. **Bundle and type identifiers.** The app is `com.example.enrollmentbundlestudio` and the project document type is `com.example.enrollmentbundlestudio.project`. Keep the document type identifier fixed after the first release; changing it breaks file association for existing projects.
4. **Document memory model.** The managed folders are held in memory. That suits icons and scripts. Bundled installers (an advanced Phase 3 option) must not live in `Scripts/`; they will be referenced from a separate preserved folder.
5. **Builds folder and open documents.** Writing into the project's `Builds/` while it is open needs coordinated file access. Phase 4 writes packages to the output folder by default and copies reports into `Builds/` through `NSFileCoordinator`.
6. **ADE timing.** Intune may install the package before login, and swiftDialog itself may arrive later. The daemon design and bounded waits address this, but the overall timeout and Intune app assignment order need testing in your tenant.
7. **Intune package rules.** Requirements differ between the macOS LOB app type and the unmanaged macOS PKG app type (signing, scripts, detection). Verify against current Microsoft documentation before choosing one; the builder supports signed and unsigned output.
8. **Catalogue drift.** Vendors change bundle identifiers and paths (Teams already has). Treat the catalogue as defaults and verify on a test device.
9. **swiftDialog drift.** Command-file vocabulary and JSON keys evolve between swiftDialog releases. The minimum version setting and one shared library limit the impact.
10. **Bash 3.2 parallelism.** There is no `wait -n`; the runner polls child PIDs with `kill -0`, which is simple but needs careful timeout handling.
11. **Placeholder insertion.** SwiftUI on macOS 13 does not expose the text cursor, so Insert appends. A cursor-aware `NSTextView` wrapper can replace it later without model changes.
12. **Undo granularity.** Typing and the color picker create fine-grained undo steps. Acceptable for Phase 1.
