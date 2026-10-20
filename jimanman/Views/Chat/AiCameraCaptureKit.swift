import AVFoundation
import CoreMotion
import SwiftUI
import UIKit
import Vision

// MARK: - Models

enum CaptureSearchMode {
    case single
    case fullPage
}

struct CropRectPx: Equatable {
    var left: CGFloat
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat

    var width: CGFloat { right - left }
    var height: CGFloat { bottom - top }

    func contains(_ point: CGPoint) -> Bool {
        point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
    }
}

struct CropRectRatio: Equatable {
    var left: CGFloat
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat
}

struct CameraFrameSpec: Equatable {
    let previewWidthPx: CGFloat
    let previewHeightPx: CGFloat
    let frameRect: CropRectPx
    let mode: CaptureSearchMode
}

// MARK: - Image Processing

enum AiImageCropProcessor {
    static func nextShortImageName(prefix: String) -> String {
        "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
    }

    static func fixOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up, let cgImage = image.cgImage else { return image }

        var transform = CGAffineTransform.identity
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        var outputWidth = width
        var outputHeight = height

        switch image.imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: width, y: height).rotated(by: .pi)
        case .left, .leftMirrored:
            outputWidth = height
            outputHeight = width
            transform = transform.translatedBy(x: width, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored:
            outputWidth = height
            outputHeight = width
            transform = transform.translatedBy(x: 0, y: height).rotated(by: -.pi / 2)
        default:
            break
        }

        switch image.imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: width, y: 0).scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: height, y: 0).scaledBy(x: -1, y: 1)
        default:
            break
        }

        guard let context = CGContext(
            data: nil,
            width: Int(outputWidth),
            height: Int(outputHeight),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else {
            return image
        }

        context.concatenate(transform)
        let drawRect: CGRect
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            drawRect = CGRect(x: 0, y: 0, width: height, height: width)
        default:
            drawRect = CGRect(x: 0, y: 0, width: width, height: height)
        }
        context.draw(cgImage, in: drawRect)
        guard let normalized = context.makeImage() else { return image }
        return UIImage(cgImage: normalized, scale: image.scale, orientation: .up)
    }

    static func cropCapturedPhotoByFrame(image: UIImage, frameSpec: CameraFrameSpec) -> UIImage? {
        let bitmap = fixOrientation(image)
        guard let cgImage = bitmap.cgImage else { return nil }
        let previewW = max(frameSpec.previewWidthPx, 1)
        let previewH = max(frameSpec.previewHeightPx, 1)
        let scale = max(previewW / CGFloat(cgImage.width), previewH / CGFloat(cgImage.height))
        let displayedW = CGFloat(cgImage.width) * scale
        let displayedH = CGFloat(cgImage.height) * scale
        let offsetX = (previewW - displayedW) / 2
        let offsetY = (previewH - displayedH) / 2

        func mapX(_ x: CGFloat) -> Int {
            Int((((x - offsetX) / scale)).rounded()).clamped(to: 0...cgImage.width)
        }
        func mapY(_ y: CGFloat) -> Int {
            Int((((y - offsetY) / scale)).rounded()).clamped(to: 0...cgImage.height)
        }

        let frame = frameSpec.frameRect
        var left = mapX(frame.left)
        var top = mapY(frame.top)
        var right = mapX(frame.right)
        var bottom = mapY(frame.bottom)
        if right <= left || bottom <= top {
            left = 0; top = 0; right = cgImage.width; bottom = cgImage.height
        }
        let cropRect = CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
        guard let cropped = cgImage.cropping(to: cropRect) else { return bitmap }
        return UIImage(cgImage: cropped, scale: bitmap.scale, orientation: .up)
    }

    static func mapFrameToImageRatio(image: UIImage, frameSpec: CameraFrameSpec) -> CropRectRatio? {
        let bitmap = fixOrientation(image)
        guard let cgImage = bitmap.cgImage else { return nil }
        let bitmapWidth = CGFloat(cgImage.width)
        let bitmapHeight = CGFloat(cgImage.height)
        let previewW = max(frameSpec.previewWidthPx, 1)
        let previewH = max(frameSpec.previewHeightPx, 1)
        let scale = max(previewW / bitmapWidth, previewH / bitmapHeight)
        let displayedW = bitmapWidth * scale
        let displayedH = bitmapHeight * scale
        let offsetX = (previewW - displayedW) / 2
        let offsetY = (previewH - displayedH) / 2
        let frame = frameSpec.frameRect

        func mapX(_ x: CGFloat) -> CGFloat { ((x - offsetX) / scale / bitmapWidth).clamped(to: 0...1) }
        func mapY(_ y: CGFloat) -> CGFloat { ((y - offsetY) / scale / bitmapHeight).clamped(to: 0...1) }

        let left = mapX(frame.left)
        let top = mapY(frame.top)
        let right = mapX(frame.right)
        let bottom = mapY(frame.bottom)
        guard right > left, bottom > top else { return nil }
        return CropRectRatio(left: left, top: top, right: right, bottom: bottom)
    }

    static func fitCenterScale(imageSize: CGSize, viewport: CGSize) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        return max(min(viewport.width / imageSize.width, viewport.height / imageSize.height), 0.0001)
    }

    static func cropImage(image: UIImage, cropRect: CGRect, viewportSize: CGSize) -> UIImage? {
        let bitmap = fixOrientation(image)
        guard let cgImage = bitmap.cgImage, viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        let totalScale = fitCenterScale(imageSize: CGSize(width: cgImage.width, height: cgImage.height), viewport: viewportSize)
        let drawW = CGFloat(cgImage.width) * totalScale
        let drawH = CGFloat(cgImage.height) * totalScale
        let imageLeft = (viewportSize.width - drawW) / 2
        let imageTop = (viewportSize.height - drawH) / 2

        func clampX(_ v: CGFloat) -> Int { Int(v).clamped(to: 0...cgImage.width) }
        func clampY(_ v: CGFloat) -> Int { Int(v).clamped(to: 0...cgImage.height) }

        var left = clampX(floor((cropRect.minX - imageLeft) / totalScale))
        var top = clampY(floor((cropRect.minY - imageTop) / totalScale))
        var right = clampX(ceil((cropRect.maxX - imageLeft) / totalScale))
        var bottom = clampY(ceil((cropRect.maxY - imageTop) / totalScale))
        if right <= left || bottom <= top {
            left = 0; top = 0; right = cgImage.width; bottom = cgImage.height
        }
        let rect = CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
        guard let cropped = cgImage.cropping(to: rect) else { return bitmap }
        let result = UIImage(cgImage: cropped, scale: bitmap.scale, orientation: .up)
        let maxSide: CGFloat = 1080
        let maxDim = max(result.size.width, result.size.height)
        if maxDim <= maxSide { return result }
        let ratio = maxSide / maxDim
        let newSize = CGSize(width: result.size.width * ratio, height: result.size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        result.draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaled ?? result
    }

    static func rotate(_ image: UIImage, degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180
        var newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        if newSize.width < 1 { newSize.width = 1 }
        if newSize.height < 1 { newSize.height = 1 }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: newSize, format: format).image { ctx in
            let context = ctx.cgContext
            context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.rotate(by: radians)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    static func downscaleForOcr(_ image: UIImage, maxSide: CGFloat = 960) -> UIImage {
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > maxSide else { return image }
        let ratio = maxSide / maxDim
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaled ?? image
    }

    static func recognizeTextObservations(_ image: UIImage) -> [CGRect] {
        guard let cgImage = fixOrientation(image).cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        _ = try? handler.perform([request])
        return (request.results ?? []).map(\.boundingBox)
    }

    static func scoreUprightText(_ image: UIImage) -> Int {
        recognizeTextObservations(image).count
    }

    static func rotateToTextUpright(_ image: UIImage) -> UIImage {
        let probe = downscaleForOcr(image)
        let score0 = scoreUprightText(probe)
        let score90 = scoreUprightText(rotate(probe, degrees: 90))
        let score270 = scoreUprightText(rotate(probe, degrees: 270))
        let landscapeFirst = score90 >= score270 ? 90 : 270
        let landscapeScore = max(score90, score270)
        let landscapeOther = landscapeFirst == 90 ? score270 : score90
        let landscapeOk = landscapeScore >= score0 + 12 && landscapeScore >= landscapeOther + 18
        if landscapeOk {
            return rotate(image, degrees: CGFloat(landscapeFirst))
        }
        return image
    }

    static func detectQuestionCropRatio(_ image: UIImage) -> CropRectRatio? {
        let bitmap = fixOrientation(image)
        guard let cgImage = bitmap.cgImage else { return nil }
        let boxes = recognizeTextObservations(bitmap)
        guard !boxes.isEmpty else { return nil }
        // Vision boundingBox is normalized with origin at bottom-left.
        var left = CGFloat.greatestFiniteMagnitude
        var top = CGFloat.greatestFiniteMagnitude
        var right: CGFloat = 0
        var bottom: CGFloat = 0
        for box in boxes {
            let minX = box.minX
            let maxX = box.maxX
            let minYFromTop = 1 - box.maxY
            let maxYFromTop = 1 - box.minY
            left = min(left, minX)
            right = max(right, maxX)
            top = min(top, minYFromTop)
            bottom = max(bottom, maxYFromTop)
        }
        let padX = max(0.06, 12 / CGFloat(cgImage.width))
        let padY = max(0.05, 12 / CGFloat(cgImage.height))
        let l = max(0, left - padX)
        let t = max(0, top - padY)
        let r = min(1, right + padX)
        let b = min(1, bottom + padY)
        if r - l < 0.12 || b - t < 0.08 { return nil }
        return CropRectRatio(left: l, top: t, right: r, bottom: b)
    }

    static func initialCropRect(in viewport: CGSize, image: UIImage, ratio: CropRectRatio? = nil) -> CGRect {
        let imageSize = image.size
        let scale = fitCenterScale(imageSize: imageSize, viewport: viewport)
        let drawW = imageSize.width * scale
        let drawH = imageSize.height * scale
        let imageLeft = (viewport.width - drawW) / 2
        let imageTop = (viewport.height - drawH) / 2
        if let ratio {
            return CGRect(
                x: imageLeft + drawW * ratio.left,
                y: imageTop + drawH * ratio.top,
                width: drawW * (ratio.right - ratio.left),
                height: drawH * (ratio.bottom - ratio.top)
            )
        }
        let margin: CGFloat = 24
        return CGRect(
            x: imageLeft + margin,
            y: imageTop + margin,
            width: max(80, drawW - margin * 2),
            height: max(80, drawH - margin * 2)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private func floor(_ value: CGFloat) -> CGFloat { Foundation.floor(value) }

// MARK: - Orientation

enum CaptureVideoOrientation {
    static func avOrientation(for mode: CaptureSearchMode) -> AVCaptureVideoOrientation {
        switch mode {
        case .single: return .landscapeRight
        case .fullPage: return .portrait
        }
    }

    static func apply(_ orientation: AVCaptureVideoOrientation, to connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
    }
}

enum AppOrientationController {
    static func setCameraMode(_ mode: CaptureSearchMode?) {
        if mode == .single {
            AppDelegate.orientationMask = .landscape
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        } else if mode == .fullPage {
            AppDelegate.orientationMask = .portrait
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        } else {
            AppDelegate.orientationMask = .allButUpsideDown
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

// MARK: - Camera Session

final class CameraSessionController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isReady = false
    @Published var isCapturing = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private(set) var captureMode: CaptureSearchMode = .single

    func updateCaptureMode(_ mode: CaptureSearchMode) {
        captureMode = mode
        applyVideoOrientation()
    }

    func applyVideoOrientation() {
        let orientation = CaptureVideoOrientation.avOrientation(for: captureMode)
        CaptureVideoOrientation.apply(orientation, to: photoOutput.connection(with: .video))
    }

    func start() {
        guard !session.isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureSession() }
                }
            }
        default:
            break
        }
    }

    func stop() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
            }
        }
        isReady = false
    }

    private func configureSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()
            self.applyVideoOrientation()
            self.session.startRunning()
            DispatchQueue.main.async { self.isReady = true }
        }
    }

    func capturePhoto(orientation: AVCaptureVideoOrientation = .portrait, completion: @escaping (UIImage?) -> Void) {
        guard isReady, !isCapturing else { completion(nil); return }
        isCapturing = true
        captureCompletion = completion
        CaptureVideoOrientation.apply(orientation, to: photoOutput.connection(with: .video))
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer {
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.captureCompletion?(nil) }
            return
        }
        DispatchQueue.main.async {
            self.captureCompletion?(AiImageCropProcessor.fixOrientation(image))
        }
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    let mode: CaptureSearchMode

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.captureMode = mode
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.captureMode = mode
        uiView.applyVideoOrientation()
    }

    final class PreviewView: UIView {
        var captureMode: CaptureSearchMode = .single

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyVideoOrientation()
        }

        func applyVideoOrientation() {
            let orientation = CaptureVideoOrientation.avOrientation(for: captureMode)
            CaptureVideoOrientation.apply(orientation, to: videoPreviewLayer.connection)
        }
    }
}

// MARK: - UI Components

struct CaptureModeChip: View {
    let text: String
    let active: Bool
    var enabled: Bool = true
    var backgroundColor: Color? = nil
    var textColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: active ? .bold : .regular))
                .foregroundColor(enabled ? (textColor ?? .white) : (textColor ?? .white).opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        enabled
                            ? (backgroundColor ?? (active ? Color(hex: "00D7CD") : Color.black.opacity(0.2)))
                            : (backgroundColor ?? (active ? Color(hex: "00D7CD") : Color.black.opacity(0.2))).opacity(0.45)
                    )
                )
        }
        .disabled(!enabled)
    }
}

struct CameraCaptureOverlayView: View {
    let onDismiss: () -> Void
    let onPickFromAlbum: () -> Void
    let onImageCaptured: (UIImage, CameraFrameSpec) -> Void
    var onCaptureFailed: (String) -> Void = { _ in }

    @StateObject private var camera = CameraSessionController()
    @StateObject private var motion = CaptureMotionController()
    @State private var previewSize: CGSize = .zero
    @State private var correcting = false

    var body: some View {
        GeometryReader { geo in
            CameraCaptureOverlayCanvas(
                size: geo.size,
                camera: camera,
                buttonSpin: motion.buttonSpin,
                capturing: camera.isCapturing || correcting,
                onPickFromAlbum: onPickFromAlbum,
                onDismiss: onDismiss,
                onCapture: { frame in capture(frame: frame, previewSize: geo.size) }
            )
            .onAppear { previewSize = geo.size }
            .onChange(of: geo.size) { previewSize = $0 }
        }
        .ignoresSafeArea()
        .onAppear {
            camera.updateCaptureMode(.fullPage)
            camera.start()
            motion.start()
            AppOrientationController.setCameraMode(.fullPage)
        }
        .onDisappear {
            motion.stop()
            camera.stop()
            AppOrientationController.setCameraMode(nil)
        }
    }

    private func capture(frame: CGRect, previewSize: CGSize) {
        guard camera.isReady else {
            onCaptureFailed("相机未就绪，请稍候")
            return
        }
        let spec = CameraFrameSpec(
            previewWidthPx: previewSize.width,
            previewHeightPx: previewSize.height,
            frameRect: CropRectPx(left: frame.minX, top: frame.minY, right: frame.maxX, bottom: frame.maxY),
            mode: .fullPage
        )
        camera.capturePhoto(orientation: motion.captureOrientation) { image in
            guard let image else {
                onCaptureFailed("拍照失败，请重试")
                return
            }
            correcting = true
            DispatchQueue.global(qos: .userInitiated).async {
                let upright = AiImageCropProcessor.rotateToTextUpright(AiImageCropProcessor.fixOrientation(image))
                DispatchQueue.main.async {
                    correcting = false
                    onImageCaptured(upright, spec)
                }
            }
        }
    }
}

final class CaptureMotionController: ObservableObject {
    @Published var buttonSpin: Double = 0

    var captureOrientation: AVCaptureVideoOrientation {
        switch buttonSpin {
        case 90: return .landscapeLeft
        case 270: return .landscapeRight
        default: return .portrait
        }
    }

    private let motion = CMMotionManager()
    private var landscapeSide = 0
    private var lastOrientation = -1

    func start() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.08
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handle(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z)
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }

    private func handle(x: Double, y: Double, z: Double) {
        var angle = atan2(-x, y) * 180 / .pi
        if angle < 0 { angle += 360 }
        lastOrientation = Int(angle.rounded())
        let ax = abs(x), ay = abs(y), az = abs(z)
        let layingFlat = az >= 0.66 && az >= ax && az >= ay
        if !layingFlat {
            let stayLeft = lastOrientation >= 50 && lastOrientation <= 130
            let stayRight = lastOrientation >= 230 && lastOrientation <= 310
            let enterLeft = lastOrientation >= 75 && lastOrientation <= 105
            let enterRight = lastOrientation >= 255 && lastOrientation <= 285
            if landscapeSide == 1 && stayLeft {
                landscapeSide = 1
            } else if landscapeSide == 2 && stayRight {
                landscapeSide = 2
            } else if enterLeft {
                landscapeSide = 1
            } else if enterRight {
                landscapeSide = 2
            } else if !stayLeft && !stayRight {
                landscapeSide = 0
            }
        }
        let spin: Double
        switch landscapeSide {
        case 1: spin = 270
        case 2: spin = 90
        default: spin = 0
        }
        if buttonSpin != spin { buttonSpin = spin }
    }
}

private struct CameraCaptureOverlayCanvas: View {
    let size: CGSize
    @ObservedObject var camera: CameraSessionController
    let buttonSpin: Double
    let capturing: Bool
    var onPickFromAlbum: () -> Void
    var onDismiss: () -> Void
    var onCapture: (CGRect) -> Void

    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
    }

    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
    }

    private var frameRect: CGRect {
        let sidePad: CGFloat = 10
        let albumRow: CGFloat = 52
        let buttonRow: CGFloat = 56
        let topReserved = safeTop + albumRow
        let bottomReserved = safeBottom + buttonRow + 12
        let width = max(size.width - sidePad * 2, 160)
        let height = max(size.height - topReserved - bottomReserved, 160)
        let left = max((size.width - width) / 2, 0)
        let top = topReserved
        return CGRect(x: left, y: top, width: width, height: min(height, size.height - bottomReserved - top))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            CameraPreviewRepresentable(session: camera.session, mode: .fullPage)
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.72), lineWidth: 2)
                .frame(width: frameRect.width, height: frameRect.height)
                .offset(x: frameRect.minX, y: frameRect.minY)
            VStack(spacing: 8) {
                Text("+")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(Color.white.opacity(0.95))
                Text("对准题目即可拍照")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.92))
            }
            .rotationEffect(.degrees(buttonSpin))
            .frame(width: frameRect.width, height: frameRect.height)
            .offset(x: frameRect.minX, y: frameRect.minY)

            HStack {
                Spacer(minLength: 0)
                CaptureModeChip(text: "相册", active: false, enabled: !capturing, action: onPickFromAlbum)
                    .rotationEffect(.degrees(buttonSpin))
                    .padding(.trailing, 16)
            }
            .padding(.top, safeTop + 8)

            HStack {
                if capturing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00D7CD")))
                            .frame(width: 22, height: 22)
                        Text("正在校正方向")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .rotationEffect(.degrees(buttonSpin))
                } else {
                    CaptureModeChip(
                        text: "拍照",
                        active: true,
                        enabled: camera.isReady,
                        backgroundColor: .white,
                        textColor: Color(hex: "0F172A"),
                        action: { onCapture(frameRect) }
                    )
                    .rotationEffect(.degrees(buttonSpin))
                }
                Spacer(minLength: 0)
                CaptureModeChip(
                    text: "取消",
                    active: false,
                    enabled: !capturing,
                    backgroundColor: Color(hex: "64748B"),
                    textColor: .white,
                    action: onDismiss
                )
                .rotationEffect(.degrees(buttonSpin))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, safeBottom + 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct CameraCaptureConfirmView: View {
    let image: UIImage
    let onRetake: () -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("确认题目图片")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "0F172A"))
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .background(Color(hex: "F1F5F9"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("请确认题目完整且清晰，再进入答疑")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "64748B"))
                HStack(spacing: 10) {
                    confirmButton("取消", bg: Color(hex: "64748B"), action: onCancel)
                    confirmButton("重拍", bg: Color(hex: "94A3B8"), action: onRetake)
                    confirmButton("使用该图片", bg: AppColors.primary, bold: true, action: onConfirm)
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
    }

    private func confirmButton(_ title: String, bg: Color, bold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: bold ? .bold : .regular))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(bg, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct ImageCropDialogView: View {
    let sourceImage: UIImage
    let initialRatio: CropRectRatio?
    var allowRetake: Bool = false
    var onRetake: () -> Void = {}
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    @State private var workingImage: UIImage
    @State private var autoRatio: CropRectRatio?
    @State private var detecting = true
    @State private var loading = false
    @State private var viewportSize: CGSize = .zero
    @State private var cropRect: CGRect = .zero
    @State private var dragStartRect: CGRect = .zero
    @State private var activeDrag: CropDragKind?
    @State private var userAdjusted = false

    init(
        sourceImage: UIImage,
        initialRatio: CropRectRatio?,
        allowRetake: Bool = false,
        onRetake: @escaping () -> Void = {},
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (UIImage) -> Void
    ) {
        self.sourceImage = sourceImage
        self.initialRatio = initialRatio
        self.allowRetake = allowRetake
        self.onRetake = onRetake
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _workingImage = State(initialValue: sourceImage)
        _autoRatio = State(initialValue: initialRatio)
    }

    private enum CropDragKind: Hashable {
        case move
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right

        var isCorner: Bool {
            switch self {
            case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
            default: return false
            }
        }
    }

    private var hintText: String {
        if detecting { return "正在自动框选题目…" }
        if autoRatio != nil { return "已自动框选题目，可拖动或拉四角调整" }
        return "可拖动裁剪框和四边四角调整范围"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("裁剪图片")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "1F2937"))
                Spacer()
                Button("✕", action: onCancel)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "6B7280"))
                    .disabled(loading)
            }
            HStack {
                Text(hintText)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "6B7280"))
                Spacer()
                Button("旋转") { rotateWorkingImage() }
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "00AFA4"))
                    .disabled(loading || detecting)
            }
            ZStack {
                Color(hex: "F3F4F6")
                cropCanvas
                if detecting || loading {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                cropAction("取消", color: Color(hex: "334155"), bg: Color(hex: "E2E8F0"), action: onCancel)
                if allowRetake {
                    cropAction("重拍", color: Color(hex: "0F766E"), bg: Color(hex: "E2E8F0"), action: onRetake)
                }
                Button(action: confirmCrop) {
                    Text("确定")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background((loading || detecting) ? Color(hex: "94A3B8") : Color(hex: "00AFA4"), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(loading || detecting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .onAppear { runAutoDetect(resetRect: true) }
    }

    private func cropAction(_ title: String, color: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(bg, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(loading)
    }

    private func runAutoDetect(resetRect: Bool) {
        detecting = true
        userAdjusted = false
        let image = workingImage
        DispatchQueue.global(qos: .userInitiated).async {
            let ratio = AiImageCropProcessor.detectQuestionCropRatio(image) ?? initialRatio
            DispatchQueue.main.async {
                autoRatio = ratio
                detecting = false
                if resetRect, viewportSize.width > 0 {
                    cropRect = AiImageCropProcessor.initialCropRect(in: viewportSize, image: image, ratio: ratio)
                }
            }
        }
    }

    private func rotateWorkingImage() {
        loading = true
        detecting = true
        userAdjusted = false
        let rotated = AiImageCropProcessor.rotate(workingImage, degrees: 90)
        workingImage = rotated
        DispatchQueue.global(qos: .userInitiated).async {
            let ratio = AiImageCropProcessor.detectQuestionCropRatio(rotated)
            DispatchQueue.main.async {
                autoRatio = ratio
                loading = false
                detecting = false
                if viewportSize.width > 0 {
                    cropRect = AiImageCropProcessor.initialCropRect(in: viewportSize, image: rotated, ratio: ratio)
                }
            }
        }
    }

    private func confirmCrop() {
        if let cropped = AiImageCropProcessor.cropImage(image: workingImage, cropRect: cropRect, viewportSize: viewportSize) {
            onConfirm(cropped)
        } else {
            onConfirm(workingImage)
        }
    }

    private var cropCanvas: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: workingImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRect(cropRect)
                }
                .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true))

                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)

                ForEach(handlePoints, id: \.kind) { item in
                    Circle()
                        .fill(Color.white)
                        .frame(width: item.kind.isCorner ? 22 : 16)
                        .position(item.point)
                        .gesture(dragGesture(kind: item.kind))
                }

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .gesture(dragGesture(kind: .move))
            }
            .onAppear { applyViewport(geo.size) }
            .onChange(of: geo.size) { applyViewport($0) }
        }
        .padding(8)
    }

    private struct CropHandleItem {
        let kind: CropDragKind
        let point: CGPoint
    }

    private var handlePoints: [CropHandleItem] {
        [
            CropHandleItem(kind: .topLeft, point: CGPoint(x: cropRect.minX, y: cropRect.minY)),
            CropHandleItem(kind: .topRight, point: CGPoint(x: cropRect.maxX, y: cropRect.minY)),
            CropHandleItem(kind: .bottomLeft, point: CGPoint(x: cropRect.minX, y: cropRect.maxY)),
            CropHandleItem(kind: .bottomRight, point: CGPoint(x: cropRect.maxX, y: cropRect.maxY)),
            CropHandleItem(kind: .top, point: CGPoint(x: cropRect.midX, y: cropRect.minY)),
            CropHandleItem(kind: .bottom, point: CGPoint(x: cropRect.midX, y: cropRect.maxY)),
            CropHandleItem(kind: .left, point: CGPoint(x: cropRect.minX, y: cropRect.midY)),
            CropHandleItem(kind: .right, point: CGPoint(x: cropRect.maxX, y: cropRect.midY))
        ]
    }

    private func applyViewport(_ size: CGSize) {
        viewportSize = size
        if !userAdjusted || cropRect == .zero {
            cropRect = AiImageCropProcessor.initialCropRect(in: size, image: workingImage, ratio: autoRatio ?? initialRatio)
        }
    }

    private func dragGesture(kind: CropDragKind) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if activeDrag == nil {
                    activeDrag = kind
                    dragStartRect = cropRect
                    userAdjusted = true
                }
                guard activeDrag == kind else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                var rect = dragStartRect
                switch kind {
                case .move:
                    rect.origin.x += dx
                    rect.origin.y += dy
                case .topLeft:
                    rect.origin.x += dx
                    rect.origin.y += dy
                    rect.size.width -= dx
                    rect.size.height -= dy
                case .topRight:
                    rect.origin.y += dy
                    rect.size.width += dx
                    rect.size.height -= dy
                case .bottomLeft:
                    rect.origin.x += dx
                    rect.size.width -= dx
                    rect.size.height += dy
                case .bottomRight:
                    rect.size.width += dx
                    rect.size.height += dy
                case .top:
                    rect.origin.y += dy
                    rect.size.height -= dy
                case .bottom:
                    rect.size.height += dy
                case .left:
                    rect.origin.x += dx
                    rect.size.width -= dx
                case .right:
                    rect.size.width += dx
                }
                if rect.width >= 40, rect.height >= 40 {
                    cropRect = rect.clamped(in: viewportSize)
                }
            }
            .onEnded { _ in activeDrag = nil }
    }
}

private extension CGRect {
    func clamped(in bounds: CGSize) -> CGRect {
        var r = self
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > bounds.width { r.origin.x = bounds.width - r.width }
        if r.maxY > bounds.height { r.origin.y = bounds.height - r.height }
        return r
    }
}

struct ChatAlbumPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ChatAlbumPicker
        init(_ parent: ChatAlbumPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = (info[.originalImage] as? UIImage).map { AiImageCropProcessor.fixOrientation($0) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
