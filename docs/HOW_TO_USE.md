# How to use Enrollment Bundle Studio

A step-by-step guide from an empty project to a package in Intune. Allow about 30 minutes for a first project.

## Before you start

You need:

- A Mac running macOS 13 or later, with the app built from this repository (see the README).
- Microsoft Intune, with the apps you want to wait for already assigned to your devices.
- Optional: swiftDialog installed on your Mac, for the Live Preview. The enrollment run installs it on target Macs by itself.

The app never installs software, runs your scripts or sends data anywhere while you design. Everything stays in a project folder on your Mac.

## 1. Create a project

1. Choose **File > New**. A new project starts with Company Portal in a required group and a hidden final validation task.
2. Choose **File > Save** and pick a name. A project is a folder ending in `.enrollmentproject`.

To learn the layout first, open `SampleProjects/Contoso.enrollmentproject` instead.

## 2. Fill in the Overview

Open **Overview** and set:

- **Organization name** and **project name**.
- **Bundle identifier** and **package identifier**, in reverse-DNS form such as `com.yourcompany.enrollment`.
- **Package version**, for example `1.0.0`. Raise it whenever you want Macs to run the enrollment again.
- **Output folder**: where packages are written. It defaults to Downloads.

## 3. Design the dialog in Branding

Open **Branding** and set the title, welcome message, button text, completion and failure messages, logo, optional banner and accent colour.

- Use **placeholders** to personalise text. Click one in the list to insert it into the field. Examples: `{username}`, `{computername}`, `{serialnumber}`, `{osversion}`.
- Logos and banners can be PNG, JPEG or ICNS. The app copies them into the project.
- **Blur the screen behind the dialog** dims the desktop while enrollment runs.

## 4. Add applications

Open **Applications**.

1. Click **Add from Catalogue** and pick apps such as Company Portal, Defender, Edge or OneDrive. Use **Add Custom** for anything else, with its path, bundle identifier and timeout.
2. Put apps into **groups** (for example Microsoft 365 or Security Tools). Drag to reorder, and mark a group or an app as **Required** or **Optional**.
3. Choose a **strategy** for each app:

| Strategy | What the enrollment does |
|---|---|
| Run bundled installer | Installs a package you added to the project |
| Run custom script | Runs a script from your project, then checks the app is present |
| Wait for Intune | Waits until Intune has installed the app |
| Detection only | Only checks whether the app is present |

Most apps assigned in Intune should use **Wait for Intune**. For **Run custom script**, pick the script in the app editor.

Hidden apps run in the background and do not appear in the dialog.

## 5. Add scripts

Open **Scripts**.

1. Click **Import** and choose a `.sh` or `.zsh` file. The app copies it into the project, records its SHA-256 and checks the shebang.
2. Read the checks. They flag Bash 3.2 problems, `sudo`, and unauthenticated downloads. They are hints, not a replacement for ShellCheck. If ShellCheck is installed, you can run it from the script page.
3. Set whether the script is required, visible, runs as root or as the user, its timeout, retry count and success exit codes.

Scripts are only copied and inspected. The app never runs them.

## 6. Set the order in Execution

Open **Execution** to see the order tasks will run in.

- Drag to reorder, or double-click a task to set its order, parallel group and **dependencies**.
- Tasks in the same parallel group run together.
- The app blocks circular, missing and disabled dependencies.

The Preview follows this order.

## 7. Preview and simulate

Open **Preview**.

- The **static preview** needs nothing installed. Switch scenarios, light and dark mode, and sample values or this Mac. Right-click an item to set its status.
- **Simulate** plays a timed run: waiting, running, success, failure, timeout and completion with warnings.
- **Live Preview** opens the real swiftDialog if it is installed and mirrors the preview. Nothing is executed and nothing is installed.

Check that the **Done** button locks and unlocks as you expect. It stays locked until all required tasks, including hidden ones, finish well.

## 8. Validate

Open **Validation**. Errors block the build, warnings do not.

Common errors: an invalid identifier or version, a missing script, a circular dependency, a required task that can never finish.

## 9. Build the package

Open **Package Builder**.

1. Click **Build Package**. The app builds an unsigned flat `.pkg`, verifies it and writes a build report next to it.
2. Check the result: path, size, SHA-256, identifier and version.
3. **Export Generated Files** writes the Bash framework to a folder so you can read it. **Copy Test Commands** gives you commands to test on a spare Mac.

Build History lists previous builds.

## 10. Deploy through Intune

### Manually

1. In the Intune admin centre, go to **Apps > macOS > Add**.
2. Choose **macOS app (PKG)**, which accepts unsigned packages. The **Line-of-business** type needs a signed package.
3. Upload the `.pkg`, set the minimum macOS version, and assign it to the devices or users you want.

### From the app

In **Package Builder**, click **Upload to Intune** after a verified build.

1. Enter your **tenant ID** and the **client ID** of an Entra app registration.
2. Click **Sign In and Upload**. Your default browser opens for sign-in.
3. When the upload finishes, use **Open in Intune** to assign the app.

The registration is a one-time job for an Entra administrator:

- Single tenant, platform **Mobile and desktop applications**, redirect URI `http://localhost`.
- **Allow public client flows** turned on.
- Delegated permission `DeviceManagementApps.ReadWrite.All`, with admin consent granted.

If sign-in shows `AADSTS900971`, the redirect URI is missing. If it shows "Approval required", an administrator has to grant consent.

## What happens on the Mac

When Intune installs the package, the framework runs as root. It:

1. Skips Macs that already finished (flag file `/Library/Logs/Microsoft/IntuneScripts/onBoarding/onboarding.flag`).
2. Installs swiftDialog if it is missing, verifying its signature.
3. Shows the dialog, then runs the tasks in order, updating the same window.
4. Unlocks the button when the required tasks are done.

Logs are in `/Library/Logs/Microsoft/IntuneScripts/onBoarding/`, one per run, newest 10 kept. To run it again by hand, use `enrollment.sh --force`. `--dry-run` shows what would happen without changing anything.

## Troubleshooting

| Problem | What to check |
|---|---|
| Build is blocked | Open Validation and fix the errors |
| Live Preview is unavailable | swiftDialog is not installed; the static preview and Simulate still work |
| An app never turns green | The path or bundle identifier in the app editor does not match the installed app |
| The dialog does not appear on a Mac | Check the latest log, and whether the flag file already exists |
| Upload fails after sign-in | Check the Entra permission and admin consent, and that the package is under 2 GB |

More detail is in `PACKAGING_AND_DEPLOYMENT.md`, `FRAMEWORK.md` and `PROJECT_FORMAT.md`.
