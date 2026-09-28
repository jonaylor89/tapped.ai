import RiveRuntime
import SwiftUI

/// SwiftUI wrapper around the Rive iOS runtime. Assets live in `TappedUI/Resources`.
public struct RiveView: View {
    public struct Asset: Sendable, Hashable {
        public let fileName: String
        public let stateMachine: String?
        let bundle: Bundle

        public init(fileName: String, stateMachine: String? = nil, bundle: Bundle) {
            self.fileName = fileName
            self.stateMachine = stateMachine
            self.bundle = bundle
        }

        public static let loadingLogo = Asset(fileName: "loading_logo", bundle: .module)
    }

    @State private var viewModel: RiveViewModel

    public init(_ asset: Asset, fit: RiveFit = .contain) {
        _viewModel = State(initialValue: RiveViewModel(
            fileName: asset.fileName,
            in: asset.bundle,
            stateMachineName: asset.stateMachine,
            fit: fit,
            loadCdn: false
        ))
    }

    public var body: some View {
        viewModel.view()
    }
}

#Preview("RiveView") {
    RiveView(.loadingLogo).frame(width: 200, height: 200)
}
