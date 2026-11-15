import SwiftUI

@main
struct EnrollmentBundleStudioApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: EnrollmentProjectDocument()) { file in
            ContentView(document: file.$document.skippingEqualWrites(), fileURL: file.fileURL)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            StudioCommands()
        }
    }
}
