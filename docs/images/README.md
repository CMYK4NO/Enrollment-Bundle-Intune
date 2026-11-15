# Screenshots and demo

The main README references these files. Capture them on a Mac and save them here with exactly these names.

| File | What to capture |
|---|---|
| `overview.png` | Overview section with the sample project open |
| `branding.png` | Branding editor with a logo and accent colour set |
| `applications.png` | Applications section with groups and a few apps |
| `execution.png` | Execution section showing the resolved run order |
| `preview-static.png` | Preview section, static preview, success scenario |
| `preview-warning.png` | Preview, scenario with a failed optional task (dark mode) |
| `package-builder.png` | Package Builder after a successful build |
| `splash-demo.gif` | Short recording of Preview > Simulate (or Live Preview) |

## Capturing

- Window screenshot: press ⇧⌘4, then Space, then click the window (add Option to drop the shadow).
- Use the Contoso sample project (`SampleProjects/Contoso.enrollmentproject`) so no real company data appears.
- Recording: press ⇧⌘5, choose "Record Selected Portion", and record the Simulate run (about 15 to 20 seconds).

## Converting the recording to a GIF

```bash
# QuickTime saves .mov; install ffmpeg with Homebrew if needed
ffmpeg -i demo.mov -vf "fps=12,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" splash-demo.gif
```

Keep the GIF under about 10 MB so GitHub renders it. If it is bigger, lower `fps` or `scale`.
