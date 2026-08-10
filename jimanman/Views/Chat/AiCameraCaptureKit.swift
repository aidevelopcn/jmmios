import AVFoundation
import SwiftUI
import UIKit

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

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard isReady, !isCapturing else { completion(nil); return }
        isCapturing = true
        captureCompletion = completion
        applyVideoOrientation()
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
    @State private var mode: CaptureSearchMode = .single
    @State private var previewSize: CGSize = .zero
    @State private var frameWidthPx: CGFloat = 0
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let metrics = frameMetrics(previewSize: size)
            let isFullPage = mode == .fullPage

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                CameraPreviewRepresentable(session: camera.session, mode: mode)
                    .ignoresSafeArea()

                dimmedMask(metrics: metrics, size: size)
                frameOverlay(metrics: metrics, previewSize: size)

                // 提示文案（对齐 Android TopCenter + offset contentTop）
                Text(mode == .single ? "搜单题：请横握手机，框内只保留当前题目" : "搜整页：请竖握手机，尽量铺满页面内容")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .frame(width: metrics.frameRect.width + 24)
                    .frame(maxWidth: .infinity)
                    .offset(y: metrics.contentTop)

                // 顶部模式切换（居中）
                HStack(spacing: 4) {
                    CaptureModeChip(text: "搜单题", active: mode == .single) { mode = .single }
                    CaptureModeChip(text: "搜整页", active: mode == .fullPage) { mode = .fullPage }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.4), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, isFullPage ? safeTopInset + 8 : 12)

                // 相册按钮（右上角）
                HStack {
                    Spacer(minLength: 0)
                    CaptureModeChip(text: "相册", active: false, enabled: !camera.isCapturing, action: onPickFromAlbum)
                        .padding(.trailing, isFullPage ? 16 : 88)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, isFullPage ? safeTopInset + 8 : 12)

                // 底部拍照 / 取消
                HStack {
                    if camera.isCapturing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00D7CD")))
                            .frame(width: 20, height: 20)
                            .padding(.leading, isFullPage ? 32 : 88)
                    } else {
                        CaptureModeChip(
                            text: "拍照",
                            active: true,
                            enabled: camera.isReady,
                            backgroundColor: .white,
                            textColor: Color(hex: "0F172A")
                        ) {
                            capture(metrics: metrics, previewSize: size)
                        }
                        .padding(.leading, isFullPage ? 32 : 88)
                    }

                    Spacer(minLength: 0)

                    CaptureModeChip(
                        text: "取消",
                        active: false,
                        enabled: !camera.isCapturing,
                        backgroundColor: Color(hex: "64748B"),
                        textColor: .white,
                        action: onDismiss
                    )
                    .padding(.trailing, isFullPage ? 32 : 88)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, isFullPage ? safeBottomInset + 28 : 54)
            }
            .onAppear {
                previewSize = size
                camera.updateCaptureMode(mode)
                camera.start()
                AppOrientationController.setCameraMode(mode)
                resetFrameWidth(for: size)
            }
            .onChange(of: geo.size) { newSize in
                previewSize = newSize
                resetFrameWidth(for: newSize)
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            camera.stop()
            AppOrientationController.setCameraMode(nil)
        }
        .onChange(of: mode) { newMode in
            camera.updateCaptureMode(newMode)
            AppOrientationController.setCameraMode(newMode)
            resetFrameWidth(for: previewSize)
        }
    }

    private func resetFrameWidth(for size: CGSize) {
        guard size.width > 0 else { return }
        frameWidthPx = mode == .fullPage ? size.width * 0.92 : size.width
        lastMagnification = 1
    }

    private var safeTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
    }

    private var safeBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
    }

    private struct FrameMetrics {
        let frameRect: CGRect
        let contentTop: CGFloat
    }

    private func frameMetrics(previewSize: CGSize) -> FrameMetrics {
        let isFullPage = mode == .fullPage
        let minFrameWidth: CGFloat = 160
        let topReserved: CGFloat = isFullPage ? 88 : 56
        let bottomReserved: CGFloat = isFullPage ? 148 : 118
        let availableHeight = max(previewSize.height - topReserved - bottomReserved, 120)
        let upperBound = isFullPage ? previewSize.width * 0.92 : previewSize.width
        let actualWidth = (frameWidthPx > 0 ? frameWidthPx : upperBound)
            .clamped(to: minFrameWidth...max(minFrameWidth, upperBound))
        let hintHeight: CGFloat = 44
        let frameHeight: CGFloat = {
            if isFullPage {
                return max(availableHeight - hintHeight, 120)
            }
            let fromWidth = actualWidth / 3.2
            return min(max(fromWidth, 84), availableHeight * 0.85)
        }()
        let contentTop: CGFloat = {
            if isFullPage { return topReserved }
            let contentHeight = frameHeight + hintHeight
            return topReserved + max((availableHeight - contentHeight) / 2, 0)
        }()
        let frameLeft = max((previewSize.width - actualWidth) / 2, 0)
        let frameTop = contentTop + hintHeight
        let rect = CGRect(
            x: frameLeft,
            y: frameTop,
            width: min(actualWidth, previewSize.width - frameLeft),
            height: min(frameHeight, previewSize.height - frameTop)
        )
        return FrameMetrics(frameRect: rect, contentTop: contentTop)
    }

    @ViewBuilder
    private func dimmedMask(metrics: FrameMetrics, size: CGSize) -> some View {
        let r = metrics.frameRect
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 10, height: 10))
        }
        .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func frameOverlay(metrics: FrameMetrics, previewSize: CGSize) -> some View {
        let r = metrics.frameRect
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                .frame(width: r.width, height: r.height)

            if mode == .single {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: r.height / 2))
                    path.addLine(to: CGPoint(x: r.width, y: r.height / 2))
                    path.move(to: CGPoint(x: r.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: r.width / 2, y: r.height))
                }
                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                .frame(width: r.width, height: r.height)
            }
        }
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
        .gesture(
            mode == .single ?
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastMagnification
                    lastMagnification = value
                    let upper = previewSize.width
                    frameWidthPx = (frameWidthPx > 0 ? frameWidthPx : upper) * delta
                    frameWidthPx = frameWidthPx.clamped(to: 160...max(160, upper))
                }
                .onEnded { _ in lastMagnification = 1 }
            : nil
        )
    }

    private func capture(metrics: FrameMetrics, previewSize: CGSize) {
        guard camera.isReady else {
            onCaptureFailed("相机未就绪，请稍候")
            return
        }
        let spec = CameraFrameSpec(
            previewWidthPx: previewSize.width,
            previewHeightPx: previewSize.height,
            frameRect: CropRectPx(
                left: metrics.frameRect.minX,
                top: metrics.frameRect.minY,
                right: metrics.frameRect.maxX,
                bottom: metrics.frameRect.maxY
            ),
            mode: mode
        )
        camera.capturePhoto { image in
            guard let image else {
                onCaptureFailed("拍照失败，请重试")
                return
            }
            onImageCaptured(image, spec)
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
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    @State private var viewportSize: CGSize = .zero
    @State private var cropRect: CGRect = .zero
    @State private var dragStartRect: CGRect = .zero
    @State private var activeDrag: CropDragKind?

    private enum CropDragKind {
        case move
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.53).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    Text("裁剪图片")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "1F2937"))
                    Spacer()
                    Button("✕", action: onCancel)
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "6B7280"))
                }
                Text("可拖动裁剪框和四角调整范围，底图已锁定")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "6B7280"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Color(hex: "F3F4F6")
                    cropCanvas
                }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 12) {
                    Button("取消", action: onCancel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(hex: "E5E7EB"), in: RoundedRectangle(cornerRadius: 10))
                    Button("确定") {
                        if let cropped = AiImageCropProcessor.cropImage(
                            image: sourceImage,
                            cropRect: cropRect,
                            viewportSize: viewportSize
                        ) {
                            onConfirm(cropped)
                        } else {
                            onConfirm(sourceImage)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundColor(.white)
                }
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 5)
        }
    }

    private var cropCanvas: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(cropRect)
                }
                .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true))

                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)

                ForEach(cornerPoints, id: \.0) { item in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .position(item.1)
                        .gesture(dragGesture(kind: item.0))
                }

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .gesture(dragGesture(kind: .move))
            }
            .onAppear {
                viewportSize = size
                cropRect = AiImageCropProcessor.initialCropRect(in: size, image: sourceImage, ratio: initialRatio)
            }
            .onChange(of: size) { newSize in
                viewportSize = newSize
                if cropRect == .zero {
                    cropRect = AiImageCropProcessor.initialCropRect(in: newSize, image: sourceImage, ratio: initialRatio)
                }
            }
        }
        .padding(20)
    }

    private var cornerPoints: [(CropDragKind, CGPoint)] {
        [
            (.topLeft, CGPoint(x: cropRect.minX, y: cropRect.minY)),
            (.topRight, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
            (.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
            (.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY))
        ]
    }

    private func dragGesture(kind: CropDragKind) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if activeDrag == nil {
                    activeDrag = kind
                    dragStartRect = cropRect
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
