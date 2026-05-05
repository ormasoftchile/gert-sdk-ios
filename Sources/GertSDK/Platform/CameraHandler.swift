import Foundation

#if os(iOS)
import UIKit
import AVFoundation

// CameraHandler implements `camera.capture` by presenting
// UIImagePickerController on the topmost view controller, writing the
// captured image to the app's Documents/gert-evidence directory, and
// returning a stable asset id + file URI.
//
// Why UIImagePickerController and not AVFoundation directly?
//   - It composes the full camera UI (preview, shutter, retake)
//     out of the box, which is what every routine actually wants.
//   - Permissions are handled by the system on first present.
// For headless/programmatic capture we'd swap in AVCapturePhotoOutput;
// that's not what house-chore evidence needs today.
public final class CameraHandler: NSObject, GertToolHandler, UIImagePickerControllerDelegate, UINavigationControllerDelegate, @unchecked Sendable {
    public let toolName = "camera.capture"

    private var continuation: CheckedContinuation<UIImage, Error>?

    public override init() { super.init() }

    public func isAvailable() async -> Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    public func execute(action: String, args: [String: Any]) async throws -> [String: Any] {
        let quality = (args["quality"] as? String) ?? "high"
        let jpegQuality: CGFloat = quality == "low" ? 0.4 : (quality == "medium" ? 0.7 : 0.9)

        // Fail fast on devices without a camera (e.g. the simulator).
        // UIImagePickerController.SourceType.camera will throw an
        // NSInvalidArgumentException ("Source type 1 not available")
        // if presented anyway.
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw CameraError.unavailable
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraError.permissionDenied }
        case .denied, .restricted:
            throw CameraError.permissionDenied
        default: break
        }

        let image = try await captureImage()
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw CameraError.encodingFailed
        }

        let assetID = UUID().uuidString
        let url = try writeAsset(data: data, assetID: assetID)

        return [
            "asset_id":    assetID,
            "uri":         url.absoluteString,
            "mime_type":   "image/jpeg",
            "byte_size":   data.count,
            "captured_at": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    @MainActor
    private func captureImage() async throws -> UIImage {
        guard let presenter = Self.topViewController() else {
            throw CameraError.noPresenter
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = false

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            presenter.present(picker, animated: true)
        }
    }

    private func writeAsset(data: Data, assetID: String) throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("gert-evidence", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(assetID).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - UIImagePickerControllerDelegate

    public func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage else {
            continuation?.resume(throwing: CameraError.cancelled)
            continuation = nil
            return
        }
        continuation?.resume(returning: img)
        continuation = nil
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        continuation?.resume(throwing: CameraError.cancelled)
        continuation = nil
    }

    // MARK: - Helpers

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let key = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var top = key?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

public enum CameraError: Error, LocalizedError {
    case permissionDenied
    case unavailable
    case noPresenter
    case cancelled
    case encodingFailed
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .unavailable:      return "Camera not available on this device"
        case .noPresenter:      return "No view controller available to present the camera"
        case .cancelled:        return "Camera capture cancelled"
        case .encodingFailed:   return "Failed to encode captured image"
        }
    }
}
#endif
