import SwiftUI

@main
struct GabaritScanApp: App {
    var body: some Scene {
        WindowGroup {
            ScanView()
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
    }
}
