# Packaging and deployment

## Building the package

Package Builder > **Build Package** (enabled when validation has no errors and an output folder is chosen):

1. Generates the framework and writes it to a private staging folder on the output volume. Bundled installer packages are copied and their SHA-256 is checked against the value recorded when they were attached.
2. Arranges the payload as it will appear on the Mac:
   - `<install location>/…` (the framework)
   - `/Library/LaunchDaemons/<bundle identifier>.plist`
   - install scripts: `preinstall` (stops a running enrollment for upgrades) and `postinstall` (secures the files, starts the LaunchDaemon)
3. Runs:
   ```
   /usr/bin/pkgbuild --root <payload> --scripts <scripts> --identifier <package identifier>
                     --version <package version> --install-location / --ownership recommended <file>.pkg
   ```
   This produces an **unsigned flat component package**. `--ownership recommended` records root:wheel ownership in the payload, so building needs no administrator rights.
4. Verifies the package without installing it, using `/usr/sbin/pkgutil`:
   - `--check-signature` reports the signature state (unsigned is expected)
   - `--payload-files` confirms `enrollment.sh`, `uninstall.sh`, the configuration, the libraries and the LaunchDaemon are present
   - `--expand` into a temporary folder confirms the identifier, version and both install scripts
5. Moves the package into the output folder as `<package name>-<version>.pkg` and writes `<package name>-<version>-build-report.txt` next to it. Existing files are replaced only after confirmation and go to the Trash. A failed build leaves nothing in the output folder.

Signing is intentionally not used; a flat unsigned package is the deliverable. The app has no signing settings and never reads the keychain.

Only `/usr/bin/pkgbuild` and `/usr/sbin/pkgutil` (plus an optional local ShellCheck and swiftDialog for previews) can be started, through an allowlisted runner that uses an executable path and an arguments array, never a shell command string.

## Package details for bundled installers

When you choose a package for an application, the editor reads the package's small PackageInfo files with `/usr/bin/xar` (list, then extract only those files into a temporary folder that is removed afterwards). Nothing is installed, no package script runs and the payload is not extracted. From them it suggests:

- **Application path:** the install location plus the bundle path, for example `/Applications/Microsoft Edge.app`. When the install location itself is an application folder, that is the path. Nested helper apps are ignored.
- **Bundle identifier:** the one recorded for that bundle. When the package installs into the app folder itself (for example `install-location="/Applications/Example.app"`), PackageInfo does not record it, so the editor extracts only that component's payload and reads the app's `Info.plist` with `/usr/bin/bsdtar`. If that fails, the field stays empty for you to fill in.
- **Installer receipt:** the identifier of the package component that installs the app. "Use Receipt for Detection" switches detection to the receipt; with receipt detection already selected and no value, it is filled automatically.

A package that installs no application (fonts, drivers) has no path or bundle identifier to read. When it has a single receipt, detection switches to "Installer receipt exists", and the application path may stay empty because only path and bundle identifier detection use it.  Fields you already set are never replaced silently: the editor shows what the package says and offers "Use Package Values". A package that installs several applications asks you to choose one. If the package has no application, or xar cannot read it, the editor says so and you enter the values yourself.

## Desktop wallpaper

Branding > Desktop wallpaper takes a PNG or JPEG (up to 50 MB). The image is copied into `framework/wallpaper/` and the generated `enrollment.sh` applies it once the console user's session is up, before the tasks run:

- It copies the image to `/Library/Desktop Pictures/<Organization>-Wallpaper.<ext>` so it keeps working after `uninstall.sh` removes the framework (the copy is left in place on purpose).
- It sets the wallpaper of every screen through `NSWorkspace`, scaled to "Fill Screen" (a JavaScript for Automation script run by `osascript` in the user's session with `launchctl asuser`). It sends no Apple events, so there is no "control System Events" prompt. The path is passed as an argument, so spaces and quotes are safe.
- **Users can change it afterwards.** The SHA-256 of the applied image is stored in the state directory, and the wallpaper is applied only when that fingerprint differs. A wallpaper chosen by the user is never replaced on later runs, and shipping a different image in a later bundle version applies the new image once. To force it again, delete `wallpaper.applied` from the state directory or run with `--force` after removing it.
- It never fails enrollment. If there is no console user yet it waits for a later run; if the change is refused it logs a warning and tries again on the next run.
- **No permission prompt:** the change uses `NSWorkspace`, so no PPPC (Privacy Preferences Policy Control) profile is needed for it. It sets the wallpaper of the screens attached at that moment. Not verified on a Mac yet; test it on one device.
- `--dry-run` reports whether it would apply the wallpaper; `--preview` does not touch it.

If you previously imported a wallpaper script (for example `Desktop_Wallpaper.sh`), remove it from Scripts once you use this setting, so the two do not run.

## App icons in the dialog

"Installed app icon" can only show once the app is on the Mac, because swiftDialog reads the icon from the app. To show an icon from the start, the icon has to be inside the bundle:

- **Embed App Icons** (Applications page) copies the icon of every app that is installed on the administrator's Mac into the project's `Icons` folder and switches the app to "Project image". Apps not installed on this Mac are listed so you can choose an image for them.
- Catalogue entries added from the catalogue do this automatically for apps installed on this Mac. Entries that ship their own icon (Microsoft 365) use that one.
- Icons are read from your own Mac and stay in the project; nothing is downloaded.

## Intune detection app

The package installs a small placeholder app, `<Organization> Bundle.app`, whose bundle identifier is the package identifier and whose version is the package version. Intune's macOS PKG app records that identifier and version as the app it expects to find (`includedApps`), so once the placeholder is on the Mac Intune sees the app as installed and does not run the policy again. The placeholder does nothing when opened.

- **Where:** Settings → Device locations → *Detection app folder*. Empty means the install location. If Intune does not detect it there, try `/Applications` and rebuild.
- `uninstall.sh` removes it. Nothing in the folder other than the app is touched.
- **Not verified against a tenant.** Intune finds apps through the macOS app inventory, so test one Mac: install the package, check the app shows as installed in Intune, and confirm the policy is not re-run.

## Dock

The Dock page (below Execution) sets up the Dock of the user who is logged in when the enrollment finishes.

- **Apps** come from the project's Applications page (the Dock follows later edits of their name and path), from a list of macOS apps, or from any path you type or choose. Reorder by dragging.
- **Remove default items** on: the Dock shows only the listed apps (`persistent-apps` is replaced; folders such as Downloads and the Trash stay). Off: the listed apps are added to the Dock the user already has, skipping apps that are already in it.
- **Position, icon size and auto-hide** are written with the apps.
- It runs once, **after the tasks, and only when the outcome is success or complete with warnings**, as the console user (`launchctl asuser`), then restarts the Dock. Apps that are not installed at that moment are skipped and logged. If none of the apps are installed, the Dock is left unchanged and tried again on a later run.
- **Users can rearrange the Dock afterwards.** A fingerprint of the configuration is stored in the state directory after a successful change, and the Dock is not touched again until a different configuration is shipped (a changed app list, position, size, auto-hide or mode).
- It never fails enrollment. `--dry-run` reports what it would do; `--preview` does not touch the Dock.

If you previously imported a Dock script (for example `Configure_Dock.sh`), remove it from Scripts once you use this page, otherwise both run.

## Build report

Plain text, next to the package. It contains:
- **Build:** project name and ID, organization, build date, application, enrollment bundle and package versions, package identifier, install location, LaunchDaemon.
- **Package:** output path, size, SHA-256, signature state and every verification check.
- **Validation:** error, warning and information counts, and the non-informational issues.
- **Contents:** included applications (strategy, required state, attached packages with hashes), scripts (path, interpreter, context, hash), and required and optional tasks.
- **Inventory:** the generated file list.

Script contents and script output are never included.

## Build history

Each successful build is recorded per project in `~/Library/Application Support/Enrollment Bundle Studio/BuildHistory/<project ID>.json`, so building never edits the open project. Build History lists builds newest first, with:
- Reveal in Finder, Open Report and Copy SHA-256
- a note when a package file has been moved or deleted

Removing an entry never deletes files.

## Deploying with Microsoft Intune

1. **swiftDialog** is installed automatically by the enrollment framework (official release, signature checked). To control the version or avoid internet access from devices, deploy it yourself as its own Intune app; the framework then finds it and installs nothing.
2. **Deploy the apps** your project waits for (Company Portal, Defender, Microsoft 365 and so on) as usual in Intune. The enrollment bundle detects them; it does not install them unless you attached a package.
3. **Upload the enrollment package** as a macOS app and assign it to the enrollment device group. Two guards keep onboarded Macs from being onboarded again. The framework itself skips the run on Macs that already have the onboarding flag and on Macs whose MDM enrollment is older than the enrollment window (default 20 hours); on its own the package would still copy its files to them. The **Intune pre-install script** (`intune/pre-install.sh` in the export, set automatically by *Upload to Intune*) goes one step further: on a Mac that has the onboarding flag it exits 1, so Intune does not install the package at all. It logs to `/Library/Logs/Microsoft/IntuneScripts/onBoarding/`. Intune may show that install as failed on such Macs; confirm how your tenant reports it on one Mac that has the flag before a broad rollout. The script also blocks a newer bundle version on already-onboarded Macs; remove the flag file to onboard a Mac again. If you upload by hand, paste the file into the app's *Pre-install script* setting.
4. On Automated Device Enrollment the package can install before anyone logs in. The LaunchDaemon then waits for the console user and shows the dialog. It repeats at every boot until enrollment succeeds, then removes itself.

> Intune's macOS app types differ in their package requirements, including whether unsigned packages are accepted. Confirm against current Microsoft documentation that the app type you choose accepts an unsigned flat package before rolling out.

Use the build report's SHA-256 to confirm that the file uploaded to Intune is the one you built and tested.

## Testing before rollout

- **Without installing:** Package Builder > Export Generated Files, then **Copy Test Commands** and paste them into Terminal on a test Mac. This copies the framework into place and runs `--dry-run` and `--preview`. The commands contain the exact export folder and install location, quoted.
- **Full test:** install the package on a test Mac (`sudo installer -pkg <file>.pkg -target /`). This starts enrollment immediately. Logs are in `/Library/Logs/Microsoft/IntuneScripts/onBoarding/`; remove everything afterwards with `sudo "<install location>/uninstall.sh"`.

## Preparing the app for internal distribution

1. Identifiers are set: the app is `com.example.enrollmentbundlestudio` and documents are `com.example.enrollmentbundlestudio.project`. Keep the document identifier fixed.
2. Archive a Release build (Hardened Runtime is on for Release), sign it with your Developer ID Application certificate, notarize and staple:
   ```
   xcrun notarytool submit "Enrollment Bundle Studio.zip" --keychain-profile "notary" --wait
   xcrun stapler staple "Enrollment Bundle Studio.app"
   ```
   This concerns the Studio app itself, not the enrollment packages it builds. Store notarization credentials with `xcrun notarytool store-credentials`; never in the project.
3. Distribute the app to administrators' Macs with Intune.

## Uploading to Intune from the app

After a successful build, Package Builder > Last build > **Upload to Intune…** uploads the package as an Intune **macOS app (PKG)**. This is the unmanaged PKG app type, which accepts unsigned packages (the line-of-business app type requires a Developer ID Installer signature).

The upload is the only feature that sends data over the network, and it runs only when you press **Upload to Intune**. It needs the Microsoft Entra tenant ID and client ID entered in **Settings > Microsoft Entra**; until both are set, the upload button is disabled.

**Sign-in.** Nothing signs in when the app starts. The first time you press **Upload to Intune**, your default browser opens for Microsoft Entra sign-in (authorization code flow with PKCE, redirect to `http://localhost:<port>` on this Mac). The tenant ID and application (client) ID come from Settings, where you enter the values of your own app registration; they are identifiers, not secrets, there is no client secret, and nothing is built into the app. They are stored in this Mac's preferences, never in a project, a configuration export or a package. A sign-in is tied to the IDs it was made with, so changing them in Settings requires a new sign-in. The tokens are kept in memory only and never written to disk. The access token is renewed silently while the app runs, and the browser opens again only if that fails. The upload then continues and offers **Open in Intune** when it is done.

**One-time Entra setup** (by a tenant administrator):
1. Entra admin center > App registrations > New registration (single tenant).
2. Authentication > Add a platform > Mobile and desktop applications, redirect URI `http://localhost`; turn on *Allow public client flows*.
3. API permissions > Microsoft Graph > Delegated > `DeviceManagementApps.ReadWrite.All` and `offline_access`; grant admin consent.
4. Copy the Directory (tenant) ID and Application (client) ID from the registration's Overview page into **Settings > Microsoft Entra** in the app. To use another registration, replace the two IDs there.

The person signing in needs an Intune role that can add apps (for example Application Manager).

**What the app does** (Microsoft Graph beta, `deviceAppManagement/mobileApps`):
1. Creates a `macOSPkgApp` (name, publisher, description, package identifier and version as the included app, minimum macOS, version detection ignored), and the pre-install script (`preInstallScript`, Base64). If Intune rejects the app with the script (HTTP 400), the app is created again without it and the sheet tells you to paste `intune/pre-install.sh` into the app's Pre-install script setting by hand.
2. Creates a content version and a file entry, encrypts the package (AES-256-CBC with an HMAC, the Intune app upload format) into a temporary file, and uploads it to Azure Storage in 6 MB blocks.
3. Commits the file with its encryption information, waits for Intune to accept it, then sets the committed content version.
4. Removes the temporary file. If a step fails or you cancel after the app was created, the app is deleted again on a best-effort basis.

Afterwards open the app in Intune (the sheet offers a link), check the detection rules and assign it to the enrollment group. Graph lists minimum macOS values only up to 26.0, so a project with minimum macOS 27 is uploaded as 26.0; adjust it in Intune if needed. The limit for macOS apps is 2 GB. The Graph beta API can change without notice.
