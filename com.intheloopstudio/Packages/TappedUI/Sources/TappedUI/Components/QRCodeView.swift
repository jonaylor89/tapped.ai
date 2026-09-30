import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// CoreImage QR code generator (share profile).
public enum QRCode {
    /// Returns a crisp `CGImage` for `string`, rendered in `foreground` on a transparent background.
    public static func image(for string: String, scale: CGFloat = 12, foreground: CIColor = .black) -> CGImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(string.utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage else { return nil }

        let tint = CIFilter.falseColor()
        tint.inputImage = output
        tint.color0 = foreground
        tint.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let tinted = tint.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(tinted, from: tinted.extent)
    }
}

/// Square black QR code for a string; place it on a light surface so scanners can read it in dark mode.
public struct QRCodeView: View {
    let string: String

    public init(_ string: String) {
        self.string = string
    }

    public var body: some View {
        Group {
            if let image = QRCode.image(for: string) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("qr code")
    }
}

#Preview("QRCodeView") {
    QRCodeView("https://app.tapped.ai/u/djnova")
        .frame(width: 200, height: 200)
        .padding()
}
