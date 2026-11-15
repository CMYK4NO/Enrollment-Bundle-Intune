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
3. **Upload the enrollment package** as a macOS app and assign it to the enrollment device group. No pre-install script is needed: the framework itself skips Macs that already have the onboarding flag and Macs whose MDM enrollment is older than the enrollment window (default 20 hours).
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

This is the only feature that uses the network, and it runs only when you press the button.

**Sign-in.** The app opens your default browser for Microsoft Entra sign-in (authorization code flow with PKCE, redirect to `http://localhost:<port>` on this Mac). The access token is kept in memory for that upload and is never written to disk. Only the tenant ID and application (client) ID are remembered, in the app's preferences.

**One-time Entra setup** (by a tenant administrator):
1. Entra admin center > App registrations > New registration (single tenant).
2. Authentication > Add a platform > Mobile and desktop applications, redirect URI `http://localhost`; turn on *Allow public client flows*.
3. API permissions > Microsoft Graph > Delegated > `DeviceManagementApps.ReadWrite.All`; grant admin consent.
4. Copy the Directory (tenant) ID and Application (client) ID into the upload sheet.

The person signing in needs an Intune role that can add apps (for example Application Manager).

**What the app does** (Microsoft Graph beta, `deviceAppManagement/mobileApps`):
1. Creates a `macOSPkgApp` (name, publisher, description, package identifier and version as the included app, minimum macOS, version detection ignored).
2. Creates a content version and a file entry, encrypts the package (AES-256-CBC with an HMAC, the Intune app upload format) into a temporary file, and uploads it to Azure Storage in 6 MB blocks.
3. Commits the file with its encryption information, waits for Intune to accept it, then sets the committed content version.
4. Removes the temporary file. If a step fails after the app was created, the app is deleted again on a best-effort basis.

Afterwards open the app in Intune (the sheet offers a link), check the detection rules and assign it to the enrollment group. Graph lists minimum macOS values only up to 26.0, so a project with minimum macOS 27 is uploaded as 26.0; adjust it in Intune if needed. The limit for macOS apps is 2 GB. The Graph beta API can change without notice.
