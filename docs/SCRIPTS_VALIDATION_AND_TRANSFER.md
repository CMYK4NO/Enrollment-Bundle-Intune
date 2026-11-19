# Scripts, validation, migration and transfer

## Script management

Enrollment Bundle Studio treats five activities as separate, and the Scripts page labels each one:

| Activity | What happens | Where |
| --- | --- | --- |
| Importing | The file is copied into `Scripts/`, hashed with SHA-256, its shebang and executable bit are recorded. | Scripts > Import Scripts |
| Validating | The text is checked line by line. Nothing runs. | Scripts detail, Validation page |
| Previewing | The first 400 lines are shown read-only. | Scripts detail |
| Executing | Only on devices, by the installed enrollment framework under Intune. Never on the administrator's Mac. | Device |
| Packaging | The exact file is copied into the installer with mode 755 (Phase 4). | Package Builder |

Import accepts `.sh` and `.zsh` files up to 1 MB that are UTF-8 text. Files with an unusable interpreter are still imported so you can see the problem; validation then reports an error that blocks building until you replace the file.

An imported script is **hidden from the enrollment list by default**: it still runs, in the background, but users do not see a row for it. Turn on "Show in the enrollment list" in the script's editor (or the Execution page) to show it. Scripts imported by earlier versions keep the setting they have.

If a script file is edited in Finder after import, its hash no longer matches and validation reports an error. Review the file, then choose **Accept Current File**. This keeps an unreviewed change from shipping silently.

### Built-in checks

The checks are heuristic and do not replace ShellCheck.

- **Interpreter:** missing shebang, unsupported interpreter, non-system paths such as `/opt/homebrew/bin/bash` (errors); `/usr/bin/env` (warning); `/bin/sh` (information). `/bin/zsh` scripts are fully supported and get no interpreter finding; Bash 3.2 rules do not apply to them.
- **File:** empty, not UTF-8, CRLF line endings (errors); larger than 512 KB (warning).
- **Bash 3.2 (bash and sh scripts):** associative arrays, `mapfile`/`readarray`, `${var,,}` and `${var^^}`, `&>>`, `|&`, `coproc`, `declare -n`, `${var@Q}`, Bash 4 `shopt` options, `wait -n`, `[[ -v`, negative array indexes, `;;&`, `$EPOCHSECONDS`/`$BASHPID`.
- **Security and compatibility:** `sudo`, HTTP downloads, piping downloads into a shell, `curl -k`, AppleScript administrator prompts, disabling Gatekeeper or SIP, removing quarantine, `chmod 777`, recursive deletes of `/` or unquoted variables, hard-coded secrets, `read -p` prompts, Python calls (warnings); `eval`, `set -e` (information).

### ShellCheck

If ShellCheck exists at `/opt/homebrew/bin/shellcheck` or `/usr/local/bin/shellcheck`, the Scripts detail offers **Run ShellCheck**. The script is passed on standard input with `--format=json1`; ShellCheck analyses the text and nothing is executed. ShellCheck does not analyse zsh, so the ShellCheck warning only appears when the project has bash or sh scripts. The app never installs ShellCheck.

## Execution and dependencies

An application with the "Run custom script" strategy runs its linked script as part of its own task. The script then has no row of its own in Execution or in the dialog; the application row shows the whole result. The task uses the application's order, required state, visibility, timeout and messages. Retries are the larger of the two, the user context applies if either asks for it, and the script's own dependencies are added. Other tasks that depended on the script now depend on the application. Scripts that no application links still run as separate tasks.

The task planner flattens applications, scripts and system tasks into one plan. Final validation implicitly depends on every enabled required task. The dependency graph then reports, and the Validation page lists:

| Problem | Severity |
| --- | --- |
| Duplicate or empty task identifier | Error |
| Task depends on itself | Error |
| Dependency does not exist | Error |
| Dependency is disabled | Error |
| Circular dependency (each loop reported once) | Error |
| Dependency has a higher execution order than the task | Error |
| Task shares a parallel group with its dependency | Warning |

Run order is a stable topological sort by dependencies, then execution order, then position. Consecutive tasks with the same parallel group and no dependency between them form a batch that may run together. Removing an application, group, script or system task automatically removes references to it from other tasks.

**Reordering.** On the Execution page, select a row and use Move Up or Move Down (buttons, the context menu, ⌥⌘↑ and ⌥⌘↓). The execution orders of all enabled tasks are renumbered in the new sequence (100, 110, 120, … with final validation keeping at least its own order), so the Order column always matches the run order. A task never leaves its dependencies behind: moving it up also moves the rows directly above it that it depends on, and moving it down also moves the rows directly below it that depend on it. Moves are refused while the plan has dependency cycles or duplicate identifiers, and for disabled tasks. Undo with Edit > Undo.

## Validation engine

Validation runs live on every edit. The sidebar badge shows the error count. Each issue has a severity, the affected component, a concise message and remediation guidance, and a Show button that opens the relevant page.

- **Errors block exporting and building.** Examples: missing organization name, invalid identifiers or versions, missing or changed script files, missing icons, required tasks without a success condition, unsupported interpreters, dependency errors, an unavailable output folder, and a completion button that can never unlock.
- **Warnings** deserve review. Examples: placeholder `com.example` identifiers, short timeouts, app paths missing on this Mac, ShellCheck or swiftDialog not installed, risky script patterns, Bash 4 constructs.
- **Information** explains behavior. Examples: no logo, console-user tasks waiting for a GUI session, no required tasks.

"Completion button can never unlock" is reported when the button lock is on and a required task can never complete: it depends on something missing, disabled, cyclic or blocked; it has no usable detection; its script has no success exit code or no file; or its wait condition has no command.

## Migration

`project.json` carries `schemaVersion`. On open:

- **Current:** opened normally.
- **Older and supported:** migrated in memory one step at a time on the JSON level (old files never need old Swift types). Overview shows the summary. On the next save the original file is kept as `project.schema-N.backup.json` inside the project; an existing backup is never replaced.
- **Newer:** opened read-only if it still decodes, otherwise refused. It is never overwritten.

To add a schema version: raise `AppInfo.currentSchemaVersion`, add a step to `ProjectMigrator.steps` that edits the dictionary, update the Codable model, and add a test with a fixture of the previous version.

## Export, import and duplicates

- **Export Configuration** (⌥⌘E) writes a single `.enrollmentconfig` JSON file with the project and referenced files, each with SHA-256 and size. See `PROJECT_FORMAT.md`.
- **Import Configuration** (⌥⌘I) validates everything, shows a review sheet, and saves the result as a new project, which then opens. A new project ID is assigned by default.
- **Duplicate as New Project** saves a copy with a new project ID. The standard File > Duplicate keeps the same ID; devices track enrollment state per project ID, so use the new command for real copies.

## Adding a catalogue application

Add a `CatalogEntry` to `ApplicationCatalog.entries` with a unique `id`, display name, category, absolute `.app` path, bundle identifier, optional process name, default timeout and a validation method that needs no extra value. `CatalogTests` checks the entry. Verify the path and bundle identifier on a real Mac. To ship an icon with the entry, put an `.icns` file in `EnrollmentBundleStudio/Resources/CatalogIcons/` and set `bundledIconResource` to its name without extension (Microsoft 365 does this). Adding the entry to a project copies the icon into the project's `Icons/` folder and uses it as the application icon.

## Adding a task type

1. Add the case to `TaskType` (raw values are stored in project.json, so never rename existing ones).
2. Handle it in `EnrollmentProject.addSystemTask(type:)`, the Execution page's Add menu, and `ValidationEngine.checkSystemTasks`.
3. Phase 3: add the matching Bash task template and generator mapping.
4. Add tests for planning, validation and, if it changes storage, a migration step.
