import SwiftUI

@main
struct MomentCameraApp: App {
    var body: some Scene {
        WindowGroup {
            CameraView()
                .preferredColorScheme(.dark)
        }
    }
}
