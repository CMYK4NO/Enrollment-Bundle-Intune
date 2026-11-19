# Project file format (schema version 4)

A project is a folder with the extension `.enrollmentproject`. Finder shows it as one document because the type conforms to `com.apple.package`; in Terminal it is an ordinary folder. Use Show Package Contents in Finder to inspect it.

```
MyEnrollment.enrollmentproject/
  project.json      all settings, pretty-printed, keys sorted
  Branding/         CompanyLogo.<ext>, Banner.<ext>
  Icons/            custom application icons
  Scripts/          imported scripts
  Installers/       installer packages for "Run bundled installer" (created when first used)
  project.schema-N.backup.json   written once when an older project is migrated
  Templates/        preserved, never rewritten by saves
  Generated/        preserved; export target in Phase 3
  Builds/           preserved; reports and packages in Phase 4
```

The application loads every regular, non-hidden file in `Branding/`, `Icons/` and `Scripts/`. Packages in `Installers/` are kept as file references (never loaded into memory); unreferenced packages are removed from `Installers/` on save. On save it rewrites `project.json` and those three folders: files you add in Finder are kept, files the project no longer references are kept until removed through the app, and hidden files such as `.DS_Store` are ignored and left alone. Other folders are not touched.

## project.json

| Key | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | integer | Structure version. This build writes 4 and migrates 1 to 3. |
| `applicationVersion` | string | App version that last saved the project. |
| `projectVersion` | string | Enrollment bundle version. Always equal to `settings.packageVersion`; the app keeps them in step. Raise the version to make devices re-evaluate completed tasks. |
| `id` | UUID string | Stable project identifier. |
| `createdAt`, `modifiedAt` | ISO 8601 string | UTC, whole seconds. |
| `settings` | object | See below. |
| `branding` | object | See below. |
| `applicationGroups` | array | Ordered groups of applications. |
| `scripts` | array | Imported scripts. |
| `systemTasks` | array | Tasks without a source item, such as final validation. |

### settings

`projectName`, `organizationName`, `bundleIdentifier` (reverse DNS), `packageIdentifier` (reverse DNS; both follow the organization name as `com.<organization>.enrollment` and `com.<organization>.enrollment.bundle` until edited by hand), `packageDisplayName`, `packageVersion` (1 to 4 numeric components; also the enrollment bundle version), `minimumMacOSVersion` (`26.0` or `27.0`; an older value is raised to `26.0` when the project is opened), `outputDirectoryPath` (absolute, may be empty), `installLocation`, `stateDirectory`, `windowWidth` (600 to 1600), `windowHeight` (400 to 1200), `debugLogging`, `defaultTaskTimeoutSeconds`, `maximumEnrollmentDurationSeconds`, `applicationInstallStrategy` (`waitForIntune`, `bundledInstaller`, `customScript`, `detectionOnly`), `scriptExecutionStrategy` (`sequential`, `parallelGroups`), `lockCompletionButtonUntilRequiredComplete`, `swiftDialogPath`, `swiftDialogMinimumVersion`, `onboardingFlagPath` (schema 4; empty turns the onboarding guard off), `enrollmentWindowHours` (schema 4; 1 to 720, default 20; projects saved without it get the default on load), `detectionAppDirectory` (optional; folder of the Intune detection placeholder app, absent or empty = install location).

### branding

`title`, `welcomeMessage`, `completionMessage`, `warningMessage`, `failureMessage` (inline Markdown, placeholders allowed), `buttonText`, `inProgressButtonText`, `logoPath`, `bannerPath`, `overlayIconPath` and `wallpaperPath` (optional, relative, inside `Branding/`; the wallpaper is a PNG or JPEG applied once per Mac as the desktop wallpaper; the overlay is a small badge over the dialog icon), `accentColor` (`#RRGGBB`), `completionSymbol` (SF Symbol name), `showDeviceInfo`, `infoboxTemplate`, `supportContact`, `supportURL`, `completionCommand` (shell command run once after the user clicks the completion button; default `open -a "Company Portal"`; empty runs nothing) and `completionCommandRunsAsUser` (default `true`; `false` runs it as root), `blurScreen` (default `true`; written to `dialog.json` as `blurscreen`; the dialog is never full screen).

Placeholders: `{companyname}`, `{username}`, `{userfullname}`, `{computername}`, `{computermodel}`, `{serialnumber}`, `{osversion}`, `{osname}`. Matching ignores case; unknown tokens are left as typed.

### dock (optional)

Absent when the project never configured a Dock. `isEnabled`, `removeDefaultItems`, `autoHide`, `position` (`bottom`, `left`, `right`), `tileSize` (16 to 128), and `items[]`: `id`, `source` (`project`, `system`, `manual`), `label`, `path` (absolute path of the `.app` on the managed Mac) and, for `project` items, `applicationTaskIdentifier` (the name and path then follow that application). The generated `enrollment.conf` gets `dock_*` values only when the Dock is enabled.

### applicationGroups[]

`id`, `name`, `symbolName`, `isRequired` (makes every member required), `displayBehavior` (`individualItems`, `singleSummaryItem`, `hidden`), `applications`.

### applications[]

`id`, `taskIdentifier`, `catalogID` (optional), `displayName`, `applicationPath`, `bundleIdentifier`, `processName`, `icon` `{kind, value}` where kind is `applicationBundle`, `projectAsset` (value is a path inside `Icons/`) or `sfSymbol`, `detection` `{method, value}` where method is `applicationPath`, `bundleIdentifier`, `packageReceipt`, `processRunning` or `customCommand`, `installStrategy`, `customScriptTaskIdentifier` (optional; the script a "Run custom script" app runs), `isEnabled`, `execution`, and optional `installer` (schema 3): `{relativePath, originalFilename, sha256, sizeBytes, importedAt}` where `relativePath` is `Installers/<name>.pkg`.

### execution (shared by applications, scripts and system tasks)

`isRequired`, `isVisible`, `context` (`root` or `user`), `timeoutSeconds`, `retryCount`, `dependencies` (task identifiers), `executionOrder`, `parallelGroup` (empty means sequential), `allowSkip`, `allowRerun`, `messages` `{waiting, progress, success, warning, failure}`.

### scripts[]

`id`, `taskIdentifier`, `displayName`, `relativePath` (inside `Scripts/`), `originalFilename`, `sha256` (lowercase hex of the file), `interpreter`, `sourceWasExecutable` (schema 2), `importedAt` (schema 2), `successExitCodes` (0 to 255), `execution`.

### systemTasks[]

`id`, `taskIdentifier`, `displayName`, `type` (`applicationDetection`, `packageInstallation`, `shellScript`, `intuneSync`, `waitCondition`, `configurationValidation`, `finalValidation`), `icon`, optional `detection` and `validation`, `execution`.

## Compatibility rules

- Older supported schema: migrated in memory step by step (1 → 2 adds `sourceWasExecutable` and `importedAt` to scripts). Overview shows a migration summary. The original `project.json` is written once as `project.schema-1.backup.json` on the next save; an existing backup is never overwritten.
- Schema older than any migration step: refused with an explanation.
- Newer schema: opened read-only when it still decodes, refused otherwise, never overwritten.
- Unsafe relative paths (absolute, `~`, `..`, outside the asset folders) are removed on open and listed on the Overview page.

## Version history

| Schema | Change |
| --- | --- |
| 1 | Initial format (Phase 1). |
| 2 | Scripts gain `sourceWasExecutable` and `importedAt` (Phase 2). |
| 3 | Applications gain an optional `installer` package reference (Phase 2 update). |
| 4 | Settings gain `onboardingFlagPath` and `enrollmentWindowHours` (onboarding guard). |

## Configuration export (.enrollmentconfig)

One pretty-printed JSON file, type `com.example.enrollmentbundlestudio.configuration`:

```json
{
  "format": "com.example.enrollmentbundlestudio.configuration",
  "formatVersion": 1,
  "exportedAt": "2026-11-14T09:00:00Z",
  "applicationVersion": "0.2.0",
  "schemaVersion": 2,
  "project": { "...": "the full project.json object" },
  "files": [
    { "path": "Scripts/SetComputerName.sh", "sha256": "…", "size": 610, "base64": "…" }
  ]
}
```

Only icons and scripts the project references are exported. Installer packages are never exported; on import their references are cleared with a warning so you can attach the packages again. Import checks the format identifier and version, decodes and migrates the project, and for every file checks the path (inside `Branding/`, `Icons/` or `Scripts/`, one level, no traversal), duplicates, base64, size, SHA-256 and, for images, that they decode. It also checks that every referenced file is present, that script hashes match the project, and that task identifiers are unique. Any error blocks the import; the result is always saved as a new project.
