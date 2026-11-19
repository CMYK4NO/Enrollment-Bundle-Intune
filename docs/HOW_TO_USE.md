# How to use Enrollment Bundle Studio

This guide takes you from an empty project to a tested enrollment package, step by step. Everything happens on your Mac. Nothing is installed, no script is run, and nothing is uploaded unless you press **Upload to Intune**.

## Before you start

- macOS 13 or later, and the app built or downloaded as described in the [README](../README.md).
- Optional: [swiftDialog](https://github.com/swiftDialog/swiftDialog) installed on your Mac, only for **Live Preview**. The app never installs it for you.
- Optional: a Microsoft Entra app registration, only for **Upload to Intune** (see step 11).

## 1. Create a project

**File > New** creates a project with Microsoft Company Portal in a required group and a hidden final validation task. A project is a folder with the `.ebsproject` extension, so you can inspect `project.json`, images and scripts in Finder or any editor. To explore first, **File > Open** `SampleProjects/Contoso.ebsproject`.

Save it with **File > Save** (⌘S). Pick a folder that is not Downloads or a temporary location.

## 2. Check the defaults in Settings

Open **Settings** (⌘,) and review the **Enrollment** tab before you design anything:

- the install location and state directory on the Mac
- the swiftDialog path and minimum version
- the default task timeout and the maximum enrollment duration
- the **onboarding guard** (flag path and enrollment window), which keeps already-onboarded Macs from being onboarded again

New projects start from these values. Changing them later only affects the open project once you save from Settings.

## 3. Branding

Open **Branding** and set:

- organization name, window title, welcome, completion, warning and failure messages
- accent colour, button texts, company logo and optional banner (PNG, JPEG or ICNS; images are copied into the project)
- support contact and URL
- optional desktop wallpaper (PNG or JPEG)

Use placeholders such as `{username}`, `{userfullname}`, `{computername}`, `{computermodel}`, `{serialnumber}`, `{osname}`, `{osversion}` and `{companyname}`. The list in the app has an **Insert** button for each one; it appends at the end of the field.

## 4. Add applications

Open **Applications**, then add from the catalogue (⇧⌘A) or create a custom entry. Pick how each app is handled:

| Strategy | What the enrollment does |
| --- | --- |
| **Wait for Intune** (default) | Polls the detection rule until Intune has installed the app, or the timeout ends. |
| **Detection only** | Checks once: complete or failed. |
| **Run bundled installer** | Installs a package you attached, if the app is not detected yet. The package's SHA-256 is checked first. |
| **Run custom script** | Detected like Wait for Intune. For custom installs, use a script task with a dependency instead. |

For each app, confirm the application path, bundle identifier and detection method, mark it **Required** or **Optional**, and put it in a group. **Embed App Icons** copies the icons of apps installed on your Mac into the project, so the dialog shows them from the start.

## 5. Add scripts (optional)

Open **Scripts** and import `.sh` or `.zsh` files. On import the app copies the file into the project, records its SHA-256, reads the shebang and warns about Bash 3.2 incompatibilities and common risks such as `sudo` or unauthenticated downloads. If ShellCheck is installed, you can run it on demand. **The app never runs an imported script.** Set context (root or user), timeout, retries and success exit codes per script.

## 6. Set order, dependencies and the Done button

Open **Execution**. It shows the resolved run order. Double-click a task to edit its order, parallel group and dependencies, for example "Defender validation depends on Defender detection". The completion button stays locked until every required task, visible or hidden, is in an acceptable state. The **Dock** page, below Execution, can arrange the logged-in user's Dock when enrollment succeeds.

## 7. Preview and simulate

Open **Preview**:

- **Static preview** is a native rendering and needs no swiftDialog. Switch scenarios, sample values or this Mac, and light or dark mode. Right-click an item to simulate a status.
- **Simulate** plays a timed run: waiting, running, success, failure, timeout, warnings.
- **Live Preview** opens the real swiftDialog with simulated states. Nothing is installed or executed.

## 8. Validate

Open **Validation**. Errors block exporting and building. Warnings and information are advice. Typical errors are a missing organization name, an invalid package identifier, circular dependencies, or a completion button that could never unlock. Each issue says where it is and how to fix it.

## 9. Build the package

Open **Package Builder**, choose an output folder, and press **Build Package**. The app generates the framework, builds an unsigned flat `.pkg` with `pkgbuild`, verifies it with `pkgutil` without installing it, and writes a build report next to it. Building needs no administrator rights.

Other options on the same page:

- **Export Generated Files** writes the framework as plain files so you can read it.
- **Copy Test Commands** copies Terminal commands for a test Mac.

**Build History** lists earlier builds with their SHA-256 and reports.

## 10. Test before rollout

On a test Mac:

1. Paste the commands from **Copy Test Commands** into Terminal. They run `--dry-run` and `--preview` without installing anything.
2. For a full test, install the package with `sudo installer -pkg <file>.pkg -target /`. This starts the enrollment immediately.
3. Read the logs in `/Library/Logs/Microsoft/IntuneScripts/onBoarding/`.
4. Remove everything afterwards with `sudo "<install location>/uninstall.sh"`.

## 11. Deploy with Microsoft Intune

1. Deploy swiftDialog yourself as an Intune app, or let the framework install it on the first run.
2. Deploy the apps your project waits for (Company Portal, Defender, Microsoft 365 and so on) as you normally do.
3. Upload the enrollment package as a **macOS app (PKG)** and assign it to the enrollment group. You can do this by hand in Intune, or from the app:
   1. Create your own Entra app registration (single tenant, public client). The steps are in [PACKAGING_AND_DEPLOYMENT.md](PACKAGING_AND_DEPLOYMENT.md).
   2. Open **Settings > Microsoft Entra** and enter the **Tenant ID** and **Client ID**. They are identifiers, not secrets, and they stay in this Mac's preferences, never in a project or a package.
   3. In **Package Builder**, after a verified build, press **Upload to Intune…**. Your browser opens for the Microsoft sign-in the first time.
4. Compare the build report's SHA-256 with the uploaded file.

Intune's macOS app types differ in what they accept. Check Microsoft's current documentation that your app type accepts an unsigned flat package, and test one Mac before a broad rollout.

## Sharing projects with other administrators

- **File > Export Configuration** (⌥⌘E) writes one `.ebsconfig` file with the project, referenced icons and scripts, and hashes. **Import Configuration** (⌥⌘I) checks the schema, paths and hashes before it accepts anything.
- **Duplicate as New Project** starts a copy.
- Installer packages are not included in exports. Attach them again after importing.

## Keyboard shortcuts

⌘1 to ⌘0 switch sidebar sections, ⇧⌘A opens the catalogue, ⌥⌘E exports and ⌥⌘I imports a configuration.

## Troubleshooting

- **Upload to Intune is disabled:** enter both IDs in **Settings > Microsoft Entra**.
- **Live Preview is unavailable:** swiftDialog is not installed at the path set in Settings. Static preview and Simulate still work.
- **Build Package is disabled:** fix the errors in **Validation** and choose an output folder.
- **macOS refuses to open the app:** Control-click it and choose **Open**, or use **System Settings > Privacy & Security > Open Anyway**. Release builds are not notarized unless you notarize your own.
