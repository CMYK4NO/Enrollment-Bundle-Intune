# The generated enrollment framework

Package Builder > **Export Generated Files** writes the framework to `<output folder>/<package name>-<version>-framework/`; **Build Package** builds the same files into an unsigned flat installer package (see PACKAGING_AND_DEPLOYMENT.md).

```
framework/                        installs to the project's install location
  enrollment.sh                   entry point (root)
  uninstall.sh                    removes the framework, LaunchDaemon and state; keeps logs
  VERSION
  config/enrollment.conf          project settings as quoted shell values
  config/dialog.json              swiftDialog configuration with {placeholders}
  config/tasks.json               the run plan, for people (not read by the scripts)
  lib/common.sh logging.sh state.sh user.sh network.sh dialog.sh validation.sh task-runner.sh
  tasks/010-<task id>.sh ...      one data-only file per task, in run order
  icons/  scripts/  installers/
launchd/<bundle identifier>.plist installs to /Library/LaunchDaemons
package-scripts/preinstall postinstall
README.txt
```

## Design rules

- **Task files contain only data.** Every line is a comment or `TASK_NAME='quoted value'` / `TASK_NAME=123`. All behavior lives in `lib/`, which is identical for every project and covered by tests. Project text (names, messages, paths) can never become code. The exception is commands you type yourself (custom detection and wait-condition commands), which run as root exactly as entered.
- **Task files must be root-owned and not writable by others**, or the runner refuses to load them.
- **Bash 3.2.** No associative arrays, `mapfile`, `${var,,}`, `&>>`, `wait -n`, `eval` or other Bash 4 constructs. The app's tests scan every template with the script inspector and parse every generated file with `bash -n`.
- **One swiftDialog window** per run, launched once in the user's session and updated through a command file by `lib/dialog.sh` only.

## How a run works

1. The package's `postinstall` secures the files and bootstraps the LaunchDaemon. With Automated Device Enrollment this can happen before anyone logs in.
2. `enrollment.sh` (from the LaunchDaemon, at install and at every boot until done) checks root, sets up the log, verifies the bundle, creates the protected state directory and takes the run lock.
3. It waits for a default network route (up to 5 minutes, not fatal) and for a console user whose Dock is running (up to the maximum enrollment duration).
4. Before waiting for a user, it installs swiftDialog when it is missing or older than the minimum (see swiftDialog requirements). With a user, it waits for swiftDialog (up to 10 minutes), checks its version, and opens the dialog with resolved placeholders. An optional overlay icon (Branding, Images and color) is bundled in `icons/` and set as `overlayicon` in `dialog.json`; by default there is none.
5. Tasks run batch by batch in the generated order. Tasks in one batch (same parallel group, no dependency between them) run together, at most 4 at a time. Each task has its own timeout and retries; the whole run stops at the maximum enrollment duration.
6. After each task the dialog list item, progress and, when every required task is acceptable, the completion button are updated.
7. The outcome is written to state, the dialog shows the final message, and the script waits for the user to close it (up to an hour).
8. On success (with or without warnings) the LaunchDaemon property list is removed so the run does not repeat at boot.

## Task types

| Type | Behavior |
| --- | --- |
| Application, Wait for Intune | Polls the detection rule every 10 s until it passes or the timeout ends (timed out). |
| Application, Detection only | Checks once: complete or failed. |
| Application, Run bundled installer | Complete if already detected. Otherwise verifies the package's SHA-256, runs `installer -pkg … -target /` with timeout and retries, then detects again. |
| Application, Run custom script | Complete if already detected. Otherwise runs the linked script (as root or user, with timeout, retries and the script's success codes), then detects the app, waiting up to the timeout. With no linked script it is detected like Wait for Intune. |
| Script | Runs as root or as the console user (`launchctl asuser … sudo -u`); complete when the exit code is in the success list; retries; timeout. Output goes to the log. |
| Intune synchronization | Waits for the Intune agent, then runs the optional command; a failing command gives Complete with warnings. |
| Wait condition | Polls the command until it exits 0, or times out. |
| Configuration validation | Runs the command (with retries); complete on exit 0. |
| Final validation | Complete when every required task is acceptable, otherwise failed. |

A task whose dependency did not complete is **skipped** (final validation is **failed** instead). A console-user task with nobody logged in stays **pending**, and the run ends **DEFERRED**.

## Onboarding flag

The onboarding flag (Settings > Onboarding guard; default `/Library/Logs/Microsoft/IntuneScripts/onBoarding/onboarding.flag`) marks a Mac as onboarded:

- After a run that ends in success or success with warnings, `enrollment.sh` writes the flag (root:wheel, 644) with the date, project ID, bundle version and outcome.
- A normal run that finds the flag logs "already onboarded", retires the LaunchDaemon and ends `SKIPPED`. `--force` runs anyway; `--dry-run` reports whether the flag exists; `--preview` ignores it.
- `uninstall.sh` keeps the flag so the Mac is not onboarded again. Delete it by hand to allow re-onboarding.

### Enrollment window

With the onboarding guard on, the first run on a Mac also checks how old its MDM enrollment is (Settings > Onboarding guard > Enrollment window, default 20 hours). It reads the installation date of the `Microsoft.Profiles.MDM` profile from `profiles -P -v` and skips the run (`SKIPPED`, LaunchDaemon retired) when:

1. the MDM profile or its date is missing, or the date cannot be parsed, or
2. the enrollment is older than the window.

This stops existing managed Macs from being onboarded again when the package reaches them. Only the first run on a Mac is gated (a run that resumes after a restart or logout is not), `--force` overrides it, and `--dry-run` reports what a normal run would do. With the onboarding flag left empty the window is not checked. Because a Mac without a readable MDM date is skipped, test on a device that is enrolled in Intune.

## State and resume

The state directory (project setting, mode 700, root) holds `project.id`, `bundle.version`, `last.run`, `completion`, the run lock and `tasks/<id>.status` and `.message`.

- Completed tasks are not run again unless the task allows rerunning, the **bundle version** changed, or `--force` is used.
- Failed, timed-out, skipped and interrupted tasks run again on the next run.
- A lock whose process is gone is treated as stale and replaced.
- TERM, INT and HUP stop child tasks and the dialog, keep finished work and end with `FAILED: Interrupted … will resume`.

## Run modes

| Command | What it does |
| --- | --- |
| `enrollment.sh` | Normal production run (how launchd and Intune run it). |
| `enrollment.sh --dry-run` | Checks preconditions, logs every task's plan and current detection result. No state, no dialog, no installs. |
| `enrollment.sh --preview` | Shows the real dialog to the console user with simulated progress. Changes nothing else. |
| `enrollment.sh --force` | Re-evaluates every task. |
| `enrollment.sh --help` | Usage. |

`--dry-run` wins over `--preview`. Unknown arguments are logged with `log_error` and exit 1. `uninstall.sh` supports `--dry-run` and `--help`; it refuses to remove shallow or system paths.

## Dock

When the project enables the Dock, `config/enrollment.conf` carries `dock_enabled`, `dock_remove_default`, `dock_position`, `dock_tile_size`, `dock_autohide`, `dock_fingerprint`, `dock_item_count` and `dock_item_N_label` / `dock_item_N_path`. `apply_dock` (in `lib/user.sh`) runs after the tasks when the outcome is `success` or `warnings`, before the final dialog message. It skips apps that are not installed, writes `persistent-apps`, `orientation`, `tilesize` and `autohide` as the console user, restarts the Dock, and stores the fingerprint in `state/dock.applied` so the Dock is set up once per configuration. It is never fatal.

## Logging and results

- `appname="onBoarding"`, logs in `/Library/Logs/Microsoft/IntuneScripts/onBoarding/`, one file per run (`onBoarding_YYYYMMDD-HHMMSS.log`), newest 10 kept. Directory root:wheel 755; log files 644 so the logged-in user can read them.
- Every line is timestamped. Messages appear on stderr only in a terminal. `log_error` adds one line to stderr when not in a terminal, so Intune and launchd capture failures.
- stdout carries exactly one line at the end: `STATUS: message | key=value`, with STATUS one of SUCCESS, FAILED, SKIPPED, DEFERRED, DRY-RUN, PREVIEW.
- Exit 0 for success or nothing to do; exit 1 for failure, interruption or deferral.

## swiftDialog requirements

- Installed at the project's swiftDialog path (default `/usr/local/bin/dialog`) at or above the project's minimum version (default 2.5.0). **A normal run installs or updates it automatically**: `lib/dialog.sh` reads the latest release from `https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest` (when the API fails, for example because of its per-address rate limit, it reads the release page `https://github.com/swiftDialog/swiftDialog/releases/latest` instead), downloads the `.pkg` (only from `https://github.com/swiftDialog/swiftDialog/releases/download/`), checks with `pkgutil --check-signature` that macOS trusts the signature (`Status: signed by a developer certificate issued by Apple`) and that it is signed by team `PWA5E9TQ59`, and runs `installer`. It tries three times and never fails the run. `--dry-run` and `--preview` never install it, and neither does the app's Live Preview. Devices need HTTPS access to `api.github.com` and `github.com`; if they are blocked, deploy swiftDialog with Intune instead, as the framework still waits up to 10 minutes for it.
- If swiftDialog is missing or too old, tasks still run and the problem is logged; users simply see no window.
- Statuses map to swiftDialog list states: waiting and running → `wait`, complete → `success`, complete with warnings → `error`, failed and timed out → `fail`, pending and skipped → `pending`.

## Preview and simulation in the app

- **Static preview** (no swiftDialog needed) shows the dialog natively.
- **Simulate** plays a timed run of the selected scenario: tasks advance in real run order (waiting for Intune apps, running for installers and scripts) to the scenario's final statuses.
- **Live Preview** opens the real swiftDialog with a temporary configuration and mirrors the static preview (including a running simulation and right-click status changes) through a command file, using the same command vocabulary as `lib/dialog.sh`. It runs as you, executes nothing else, never installs swiftDialog, and deletes its temporary folder when stopped, when you leave the page or when the app quits.

## Testing an export on a test Mac

Open Terminal **in the export folder** (the one with `framework/`, `launchd/`, `package-scripts/` and `README.txt`; Package Builder > Reveal in Finder shows it). The generated `README.txt` contains these commands with your project's install location filled in.

```bash
cd "/path/to/Enrollment-Bundle-1.0.0-framework"
INSTALL="/Library/Application Support/Contoso/Enrollment"   # the project's Install location (Settings)
sudo mkdir -p "$INSTALL"
sudo cp -R framework/. "$INSTALL/"
sudo chown -R root:wheel "$INSTALL"
sudo chmod -R go-w "$INSTALL"
sudo "$INSTALL/enrollment.sh" --dry-run
sudo "$INSTALL/enrollment.sh" --preview
```

Read the newest log with `sudo ls -t /Library/Logs/Microsoft/IntuneScripts/onBoarding/` and `cat` (logs are readable by every user, mode 644). Remove the test copy with `sudo "$INSTALL/uninstall.sh"`. A full run (`sudo "$INSTALL/enrollment.sh"`) installs bundled packages and runs scripts, so use a test Mac.

The dialog finds its logo, banner and icons relative to the folder it runs from, so a copy in another location still shows them. The log warns when that folder differs from the configured install location, because the LaunchDaemon and `uninstall.sh` use the configured one.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Logo or banner missing | Check that `icons/` exists next to `enrollment.sh` and that the files are readable (`chmod -R go-w` keeps them readable). |
| No dialog | Log lines about the console user and swiftDialog (missing, too old, no user). Verify `/usr/local/bin/dialog --version`. |
| `refusing to load` task file | Files must be owned by root and not writable by group or others (`chmod -R go-w`). |
| Task timed out | Raise its timeout, or check the Intune assignment for that app. Detection details are in the log. |
| Run repeats at every boot | The outcome was FAILED or DEFERRED; the LaunchDaemon stays until success. Read `completion` and `tasks/*.status` in the state directory. |
| Want to start over | `sudo …/enrollment.sh --force`, or raise the version in Overview and redeploy. |
| `Another enrollment run is active` | A run is in progress. A lock from a dead process is cleared automatically. |

## Folder and process safety

- **Install location and state directory** must be dedicated folders at least three levels deep (for example `/Library/Application Support/Contoso/Enrollment`). The app reports an error for `/`, `/Library`, `/Users` and similar, because the postinstall script changes ownership and permissions recursively. The postinstall script and `state_init` refuse the same paths on the Mac, and `uninstall.sh` uses the same check before removing anything.
- **Timeouts** stop the whole process tree of a task (children, grandchildren and so on), not only its direct children, so a timed-out user-context script cannot keep running in the background.
- **Importing a project** (configuration file or `.enrollmentproject`) shows a warning that lists the scripts, detection and validation commands and the completion command it contains, because they run on enrolled Macs, most of them as root. Review them before building.
