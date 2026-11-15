import Foundation

/// Terminal commands for testing an exported framework on a test Mac. Paths are single-quoted, so spaces
/// and special characters are safe to paste.
enum TestCommands {
    static func make(exportFolder: String, installLocation: String) -> String {
        """
        EXPORT=\(ShellQuoting.singleQuoted(exportFolder))
        INSTALL=\(ShellQuoting.singleQuoted(installLocation))
        sudo mkdir -p "$INSTALL"
        sudo cp -R "$EXPORT/framework/." "$INSTALL/"
        sudo chown -R root:wheel "$INSTALL"
        sudo chmod -R go-w "$INSTALL"
        sudo "$INSTALL/enrollment.sh" --dry-run
        sudo "$INSTALL/enrollment.sh" --preview
        # Read the newest log:
        sudo ls -t /Library/Logs/Microsoft/IntuneScripts/onBoarding/
        # Remove the test copy afterwards:
        # sudo "$INSTALL/uninstall.sh"
        """
    }
}
