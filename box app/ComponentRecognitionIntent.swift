import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct ComponentRecognitionIntent: AppIntent {
    static var title: LocalizedStringResource = "Recognize Electronic Component"

    static var description = IntentDescription("Opens the Box App to recognize an electronic component from the camera.")

    func perform() async throws -> some IntentResult {
        // It's not possible to directly control the camera from an App Intent.
        // The best we can do is open the app to the correct screen.
        // We can use a custom URL scheme to navigate to the recognition view.
        if let url = URL(string: "boxapp://recognize") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}