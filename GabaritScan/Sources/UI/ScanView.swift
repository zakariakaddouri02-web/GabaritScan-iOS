import SwiftUI

/// Pont SwiftUI ↔ UIKit pour ScanViewController
struct ScanView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> ScanViewController {
        let vc = ScanViewController()
        vc.viewModel = ScanViewModel()
        return vc
    }

    func updateUIViewController(_ uiViewController: ScanViewController, context: Context) {}
}
