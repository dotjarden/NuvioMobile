import CoreImage
import UIKit

/// Add-ons hub C, H2: renders a string as a sharp QR code (the Detail sheet's Configure section).
/// The body of `QrSignInViewModel.makeQrImage`, lifted unchanged so a second screen can use it;
/// the two older private copies (`QrSignInView`, `RemoteSetupView`) are deliberately left alone.
enum QRCode {
    /// A QR image for `string` at error-correction level M, upscaled by `scale` with a
    /// nearest-neighbour affine transform so the modules stay crisp. nil when the filter or the
    /// image cannot be produced.
    static func image(for string: String, scale: CGFloat = 14) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // The raw QR is ~30pt; scale it up sharply (nearest-neighbor via affine transform).
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
