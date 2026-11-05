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
        return jpegImage(result, maxSide: 1080, quality: 0.82) ?? result
    }

    static func jpegForUpload(_ image: UIImage) -> Data? {
        jpegImage(fixOrientation(image), maxSide: 1080, quality: 0.82)?.jpegData(compressionQuality: 0.82)
            ?? fixOrientation(image).jpegData(compressionQuality: 0.82)
    }

    private static func jpegImage(_ image: UIImage, maxSide: CGFloat, quality: CGFloat) -> UIImage? {
        let maxDim = max(image.size.width, image.size.height)
        if maxDim <= maxSide { return image }
        let ratio = maxSide / maxDim
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaled ?? image
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

    private struct OcrLine {
        let text: String
        let box: CGRect // top-left origin, normalized 0...1
    }

    private static let questionStartPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,3}\s*[、.．。:：)）]|例\s*\d*\s*[、.．:：]?|第\s*\d{1,3}\s*题|[一二三四五六七八九十]{1,3}\s*[、.．])"#
    )

    private static func recognizeChineseLines(_ image: UIImage) -> [OcrLine] {
        guard let cgImage = fixOrientation(image).cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        _ = try? handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            let box = observation.boundingBox
            return OcrLine(
                text: text,
                box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            )
        }
        .sorted { $0.box.minY < $1.box.minY }
    }

    static func scoreUprightText(_ image: UIImage) -> Int {
        let lines = recognizeChineseLines(image)
        let joined = lines.map(\.text).joined()
        let chars = joined.reduce(0) { count, ch in
            ch.isLetter || ch.isNumber || (ch >= "\u{4e00}" && ch <= "\u{9fff}") ? count + 1 : count
        }
        if chars <= 0 { return 0 }
        let lineBonus = lines.reduce(0) { $0 + ($1.box.width >= $1.box.height ? 8 : 0) }
        return chars + lineBonus + questionOrderBonus(lines) + lineInkBonus(image, lines: lines)
    }

    private static func questionOrderBonus(_ lines: [OcrLine]) -> Int {
        let startNum = try! NSRegularExpression(pattern: #"^\s*(\d{1,3})\s*[、.．。:：)）]"#)
        var numbered: [(y: CGFloat, number: Int)] = []
        for line in lines {
            let ns = line.text as NSString
            guard let match = startNum.firstMatch(in: line.text, range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges > 1 else { continue }
            let number = Int(ns.substring(with: match.range(at: 1))) ?? 0
            guard (1...199).contains(number) else { continue }
            numbered.append((line.box.midY, number))
        }
        guard numbered.count >= 2 else { return 0 }
        numbered.sort { $0.y < $1.y }
        var increasing = 0
        var decreasing = 0
        for index in 1..<numbered.count {
            if numbered[index].number > numbered[index - 1].number { increasing += 1 }
            else if numbered[index].number < numbered[index - 1].number { decreasing += 1 }
        }
        var bonus = (increasing - decreasing) * 40
        if increasing > decreasing, numbered.first!.y < 0.48 { bonus += 24 }
        if decreasing > increasing { bonus -= 24 }
        return bonus
    }

    private static func lineInkBonus(_ image: UIImage, lines: [OcrLine]) -> Int {
        var better = 0
        var worse = 0
        for line in lines {
            let box = line.box
            guard box.height > 0.012, box.width > 0.04 else { continue }
            let midY = box.midY
            let topInk = inkInRect(image, CGRect(x: box.minX, y: box.minY, width: box.width, height: midY - box.minY))
            let botInk = inkInRect(image, CGRect(x: box.minX, y: midY, width: box.width, height: box.maxY - midY))
            if CGFloat(botInk) > CGFloat(topInk) * 1.12 { better += 1 }
            else if CGFloat(topInk) > CGFloat(botInk) * 1.12 { worse += 1 }
        }
        return (better - worse) * 10
    }

    private static func inkInRect(_ image: UIImage, _ norm: CGRect) -> Int {
        guard let cgImage = fixOrientation(image).cgImage else { return 0 }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let left = Int((norm.minX * imgW).rounded()).clamped(to: 0...(cgImage.width - 1))
        let top = Int((norm.minY * imgH).rounded()).clamped(to: 0...(cgImage.height - 1))
        let right = Int((norm.maxX * imgW).rounded()).clamped(to: (left + 1)...cgImage.width)
        let bottom = Int((norm.maxY * imgH).rounded()).clamped(to: (top + 1)...cgImage.height)
        let cropW = max(1, right - left)
        let cropH = max(1, bottom - top)
        guard let cropped = cgImage.cropping(to: CGRect(x: left, y: top, width: cropW, height: cropH)) else { return 0 }
        let sampleW = min(24, cropW)
        let sampleH = min(12, cropH)
        guard let ctx = CGContext(
            data: nil,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.interpolationQuality = .low
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
        guard let data = ctx.data else { return 0 }
        let ptr = data.bindMemory(to: UInt8.self, capacity: sampleW * sampleH * 4)
        var ink = 0
        for i in 0..<(sampleW * sampleH) {
            let o = i * 4
            let lum = (Int(ptr[o]) * 299 + Int(ptr[o + 1]) * 587 + Int(ptr[o + 2]) * 114) / 1000
            if lum < 140 { ink += 1 }
        }
        return ink
    }

    static func rotateToTextUpright(_ image: UIImage) -> UIImage {
        let probe = downscaleForOcr(image)
        let score0 = scoreUprightText(probe)
        let score90 = scoreUprightText(rotate(probe, degrees: 90))
        let score270 = scoreUprightText(rotate(probe, degrees: 270))
        let landscapeFirst = score90 >= score270 ? 90 : 270
        let landscapeScore = max(score90, score270)
        let landscapeOther = landscapeFirst == 90 ? score270 : score90
        // 横拍时 90/270 都能认出横排字，分差不够就不要转，否则会整页颠倒。
        let landscapeOk = landscapeScore >= score0 + 12 && landscapeScore >= landscapeOther + 18
        if landscapeOk {
            return rotate(image, degrees: CGFloat(landscapeFirst))
        }
        return image
    }

    static func detectQuestionCropRatio(_ image: UIImage) -> CropRectRatio? {
        let bitmap = fixOrientation(image)
        let lines = recognizeChineseLines(bitmap)
        let filtered = lines.filter { line in
            let cy = line.box.midY
            return !(line.text.count <= 12 && (cy < 0.05 || cy > 0.94))
        }
        guard !filtered.isEmpty else { return nil }

        let heights = filtered.map(\.box.height).sorted()
        let lineHeight = heights[heights.count / 2]
        let gapLimit = max(lineHeight * 1.6, 0.025)

        class Question {
            var top: CGFloat
            var bottom: CGFloat
            var left: CGFloat
            var right: CGFloat
            let numbered: Bool
            init(top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, numbered: Bool) {
                self.top = top; self.bottom = bottom; self.left = left; self.right = right; self.numbered = numbered
            }
        }

        var questions: [Question] = []
        for line in filtered {
            let box = line.box
            let ns = line.text as NSString
            let startsNew = questionStartPattern.firstMatch(in: line.text, range: NSRange(location: 0, length: ns.length)) != nil
            let current = questions.last
            let farBelow = current.map { box.minY - $0.bottom > gapLimit } ?? false
            if current == nil || startsNew || (farBelow && !(current?.numbered ?? true)) {
                questions.append(Question(top: box.minY, bottom: box.maxY, left: box.minX, right: box.maxX, numbered: startsNew))
            } else if let current {
                current.bottom = max(current.bottom, box.maxY)
                current.left = min(current.left, box.minX)
                current.right = max(current.right, box.maxX)
            }
        }
        guard !questions.isEmpty else { return nil }

        let centerY: CGFloat = 0.5
        let index = questions.enumerated().min { lhs, rhs in
            func dist(_ q: Question) -> CGFloat {
                if centerY < q.top { return q.top - centerY }
                if centerY > q.bottom { return centerY - q.bottom }
                return 0
            }
            return dist(lhs.element) < dist(rhs.element)
        }?.offset ?? 0
        let chosen = questions[index]
        let nextTop = questions.indices.contains(index + 1) ? questions[index + 1].top : nil
        let bottomLimit = nextTop.map { $0 - lineHeight * 0.3 } ?? (chosen.bottom + 0.06)
        let textLeft = filtered.map(\.box.minX).min() ?? chosen.left
        let textRight = filtered.map(\.box.maxX).max() ?? chosen.right
        let padX: CGFloat = 0.03
        let padY: CGFloat = 0.015
        let l = min(max(min(chosen.left, textLeft) - padX, 0), 1)
        let r = min(max(max(chosen.right, textRight) + padX, 0), 1)
        let t = min(max(chosen.top - padY, 0), 1)
        let b = min(max(max(chosen.bottom + padY, bottomLimit), 0), 1)
        if r - l < 0.12 || b - t < 0.06 { return nil }
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
    @Published var zoomFactor: CGFloat = 1

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private(set) var captureMode: CaptureSearchMode = .single
    private var cameraDevice: AVCaptureDevice?

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
            self.cameraDevice = device
            self.session.addInput(input)
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()
            self.applyVideoOrientation()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.zoomFactor = 1
                self.isReady = true
            }
        }
    }

    var maxZoom: CGFloat {
        guard let device = cameraDevice else { return 1 }
        return min(device.activeFormat.videoMaxZoomFactor, 8)
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = cameraDevice else { return }
        let next = min(max(factor, 1), maxZoom)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = next
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.zoomFactor = next }
        } catch {}
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

private let qaCaptureBarColor = Color(hex: "00AFA4")
private let qaCaptureTopBarHeight: CGFloat = 52
private let qaCaptureBottomBarHeight: CGFloat = 112

struct QaCaptureTopBar: View {
    let title: String
    var closeEnabled: Bool = true
    var onClose: () -> Void
    var leading: AnyView? = nil
    var safeTop: CGFloat = 0

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            HStack(spacing: 0) {
                if let leading {
                    leading
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Text("✕")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!closeEnabled)
                .padding(.trailing, 6)
            }
        }
        .frame(height: qaCaptureTopBarHeight)
        .frame(maxWidth: .infinity)
        .padding(.top, safeTop)
        .background(qaCaptureBarColor)
    }
}

struct CameraCaptureOverlayView: View {
    let onDismiss: () -> Void
    let onPickFromAlbum: () -> Void
    let onImageCaptured: (UIImage, CameraFrameSpec) -> Void
    var onCaptureFailed: (String) -> Void = { _ in }
    var title: String = "绩满满答疑"

    @StateObject private var camera = CameraSessionController()
    @StateObject private var motion = CaptureMotionController()
    @State private var pinchStart: CGFloat = 1
    @State private var pinching = false

    var body: some View {
        GeometryReader { geo in
            let previewSize = CGSize(
                width: geo.size.width,
                height: max(geo.size.height - geo.safeAreaInsets.top - qaCaptureTopBarHeight - qaCaptureBottomBarHeight - geo.safeAreaInsets.bottom, 1)
            )
            CameraCaptureOverlayCanvas(
                camera: camera,
                buttonSpin: motion.buttonSpin,
                capturing: camera.isCapturing,
                title: title,
                safeTop: geo.safeAreaInsets.top,
                safeBottom: geo.safeAreaInsets.bottom,
                onPickFromAlbum: onPickFromAlbum,
                onDismiss: onDismiss,
                onCapture: { capture(previewSize: previewSize) },
                onPinchChanged: { value in
                    if !pinching {
                        pinching = true
                        pinchStart = camera.zoomFactor
                    }
                    camera.setZoom(pinchStart * value)
                },
                onPinchEnded: {
                    pinching = false
                    pinchStart = 1
                }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

    private func capture(previewSize: CGSize) {
        guard camera.isReady else {
            onCaptureFailed("相机未就绪，请稍候")
            return
        }
        let spec = CameraFrameSpec(
            previewWidthPx: previewSize.width,
            previewHeightPx: previewSize.height,
            frameRect: CropRectPx(left: 0, top: 0, right: previewSize.width, bottom: previewSize.height),
            mode: .fullPage
        )
        camera.capturePhoto(orientation: motion.captureOrientation) { image in
            guard let image else {
                onCaptureFailed("拍照失败，请重试")
                return
            }
            onImageCaptured(AiImageCropProcessor.fixOrientation(image), spec)
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
    @ObservedObject var camera: CameraSessionController
    let buttonSpin: Double
    let capturing: Bool
    let title: String
    let safeTop: CGFloat
    let safeBottom: CGFloat
    var onPickFromAlbum: () -> Void
    var onDismiss: () -> Void
    var onCapture: () -> Void
    var onPinchChanged: (CGFloat) -> Void
    var onPinchEnded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            QaCaptureTopBar(
                title: title,
                closeEnabled: !capturing,
                onClose: onDismiss,
                safeTop: safeTop
            )
            ZStack(alignment: .top) {
                CameraPreviewRepresentable(session: camera.session, mode: .fullPage)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { onPinchChanged($0) }
                            .onEnded { _ in onPinchEnded() }
                    )
                Text("对准题目拍照")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    .rotationEffect(.degrees(buttonSpin))
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            ZStack {
                qaCaptureBarColor
                Button(action: onCapture) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                        if capturing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(Color.white.opacity(camera.isReady ? 1 : 0.5))
                                .frame(width: 58, height: 58)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!camera.isReady || capturing)

                HStack {
                    Spacer()
                    Button(action: onPickFromAlbum) {
                        VStack(spacing: 4) {
                            QaAlbumGlyph()
                                .frame(width: 28, height: 28)
                            Text("相册")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(capturing)
                    .rotationEffect(.degrees(buttonSpin))
                    .padding(.trailing, 36)
                }
            }
            .frame(height: qaCaptureBottomBarHeight)
            .padding(.bottom, safeBottom)
            .background(qaCaptureBarColor)
        }
        .background(Color.black)
    }
}

private struct QaAlbumGlyph: View {
    var body: some View {
        Canvas { context, size in
            let stroke: CGFloat = 2
            let rect = CGRect(x: stroke / 2, y: stroke / 2, width: size.width - stroke, height: size.height - stroke)
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 5),
                with: .color(.white),
                lineWidth: stroke
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: size.width * 0.68 - size.width * 0.09,
                    y: size.height * 0.32 - size.width * 0.09,
                    width: size.width * 0.18,
                    height: size.width * 0.18
                )),
                with: .color(.white)
            )
            var mountain = Path()
            mountain.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.80))
            mountain.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.46))
            mountain.addLine(to: CGPoint(x: size.width * 0.60, y: size.height * 0.66))
            mountain.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.56))
            mountain.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.80))
            mountain.closeSubpath()
            context.fill(mountain, with: .color(.white))
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
    var retakeLabel: String = "重拍"
    var title: String = "框选题目"
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
        retakeLabel: String = "重拍",
        title: String = "框选题目",
        onRetake: @escaping () -> Void = {},
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (UIImage) -> Void
    ) {
        self.sourceImage = sourceImage
        self.initialRatio = initialRatio
        self.allowRetake = allowRetake
        self.retakeLabel = retakeLabel
        self.title = title
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
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                QaCaptureTopBar(
                    title: title,
                    closeEnabled: !loading,
                    onClose: onCancel,
                    leading: AnyView(
                        HStack(spacing: 0) {
                            Button(action: { rotateWorkingImage(-90) }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .disabled(loading || detecting)
                            Button(action: { rotateWorkingImage(90) }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .disabled(loading || detecting)
                        }
                        .padding(.leading, 8)
                    ),
                    safeTop: geo.safeAreaInsets.top
                )
                ZStack {
                    Color(hex: "F3F4F6")
                    cropCanvas
                    if detecting || loading {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Button(action: { if allowRetake { onRetake() } else { onCancel() } }) {
                        Text(allowRetake ? retakeLabel : "取消")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 96, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                    Spacer()
                    Button(action: confirmCrop) {
                        Text("确定")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(qaCaptureBarColor)
                            .frame(width: 96, height: 36)
                            .background(Color.white.opacity(loading || detecting ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(loading || detecting)
                }
                .padding(.horizontal, 24)
                .frame(height: 72)
                .padding(.bottom, geo.safeAreaInsets.bottom)
                .background(qaCaptureBarColor)
            }
        }
        .ignoresSafeArea()
        .background(Color(hex: "F3F4F6").ignoresSafeArea())
        .onAppear { prepareUprightAndDetect() }
    }

    private func prepareUprightAndDetect() {
        loading = true
        detecting = true
        userAdjusted = false
        let source = workingImage
        DispatchQueue.global(qos: .userInitiated).async {
            let upright = AiImageCropProcessor.rotateToTextUpright(AiImageCropProcessor.fixOrientation(source))
            let ratio = AiImageCropProcessor.detectQuestionCropRatio(upright) ?? initialRatio
            DispatchQueue.main.async {
                workingImage = upright
                autoRatio = ratio
                loading = false
                detecting = false
                if viewportSize.width > 0 {
                    cropRect = AiImageCropProcessor.initialCropRect(in: viewportSize, image: upright, ratio: ratio)
                }
            }
        }
    }

    private func rotateWorkingImage(_ degrees: CGFloat) {
        loading = true
        detecting = true
        userAdjusted = false
        let rotated = AiImageCropProcessor.rotate(workingImage, degrees: degrees)
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
                .fill(Color.black.opacity(0.47), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                CropFrameOverlay(rect: cropRect)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(cropDragGesture)
            .onAppear { applyViewport(geo.size) }
            .onChange(of: geo.size) { applyViewport($0) }
        }
        .padding(0)
    }

    private struct CropFrameOverlay: View {
        let rect: CGRect
        var body: some View {
            Canvas { context, _ in
                let r = rect
                context.stroke(Path(r), with: .color(.white), lineWidth: 3)
                context.stroke(Path(r), with: .color(Color(hex: "00AFA4")), lineWidth: 1.5)
                let len: CGFloat = 26
                let halo: CGFloat = 7
                let stroke: CGFloat = 4
                func corner(_ origin: CGPoint, dx: CGFloat, dy: CGFloat) {
                    var path = Path()
                    path.move(to: CGPoint(x: origin.x + dx, y: origin.y))
                    path.addLine(to: origin)
                    path.addLine(to: CGPoint(x: origin.x, y: origin.y + dy))
                    context.stroke(path, with: .color(.white), lineWidth: halo)
                    context.stroke(path, with: .color(Color(hex: "00AFA4")), lineWidth: stroke)
                }
                corner(CGPoint(x: r.minX, y: r.minY), dx: len, dy: len)
                corner(CGPoint(x: r.maxX, y: r.minY), dx: -len, dy: len)
                corner(CGPoint(x: r.minX, y: r.maxY), dx: len, dy: -len)
                corner(CGPoint(x: r.maxX, y: r.maxY), dx: -len, dy: -len)
                let knobs = [
                    CGPoint(x: r.minX, y: r.minY),
                    CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.minX, y: r.maxY),
                    CGPoint(x: r.maxX, y: r.maxY)
                ]
                for p in knobs {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(.white))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(Color(hex: "00AFA4")))
                }
            }
        }
    }

    private func applyViewport(_ size: CGSize) {
        viewportSize = size
        if !userAdjusted || cropRect == .zero {
            cropRect = AiImageCropProcessor.initialCropRect(in: size, image: workingImage, ratio: autoRatio ?? initialRatio)
        }
    }

    private var cropDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if activeDrag == nil {
                    guard let kind = hitKind(at: value.startLocation) else { return }
                    activeDrag = kind
                    dragStartRect = cropRect
                    userAdjusted = true
                }
                guard let kind = activeDrag else { return }
                applyDrag(kind: kind, dx: value.translation.width, dy: value.translation.height)
            }
            .onEnded { _ in activeDrag = nil }
    }

    private func hitKind(at point: CGPoint) -> CropDragKind? {
        let r = cropRect
        let corner: CGFloat = 28
        let edge: CGFloat = 22
        func near(_ a: CGPoint, _ b: CGPoint, _ d: CGFloat) -> Bool {
            abs(a.x - b.x) <= d && abs(a.y - b.y) <= d
        }
        if near(point, CGPoint(x: r.minX, y: r.minY), corner) { return .topLeft }
        if near(point, CGPoint(x: r.maxX, y: r.minY), corner) { return .topRight }
        if near(point, CGPoint(x: r.minX, y: r.maxY), corner) { return .bottomLeft }
        if near(point, CGPoint(x: r.maxX, y: r.maxY), corner) { return .bottomRight }
        if abs(point.y - r.minY) <= edge && point.x >= r.minX && point.x <= r.maxX { return .top }
        if abs(point.y - r.maxY) <= edge && point.x >= r.minX && point.x <= r.maxX { return .bottom }
        if abs(point.x - r.minX) <= edge && point.y >= r.minY && point.y <= r.maxY { return .left }
        if abs(point.x - r.maxX) <= edge && point.y >= r.minY && point.y <= r.maxY { return .right }
        if r.insetBy(dx: 8, dy: 8).contains(point) { return .move }
        return nil
    }

    private func applyDrag(kind: CropDragKind, dx: CGFloat, dy: CGFloat) {
        var rect = dragStartRect
        switch kind {
        case .move:
            rect.origin.x += dx
            rect.origin.y += dy
            cropRect = rect.clampedMove(in: viewportSize)
            return
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
        cropRect = rect.clampedResize(in: viewportSize)
    }
}

private extension CGRect {
    func clampedMove(in bounds: CGSize) -> CGRect {
        var r = self
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > bounds.width { r.origin.x = max(0, bounds.width - r.width) }
        if r.maxY > bounds.height { r.origin.y = max(0, bounds.height - r.height) }
        return r
    }

    func clampedResize(in bounds: CGSize) -> CGRect {
        var r = self
        if r.size.width < 40 {
            r.size.width = 40
        }
        if r.size.height < 40 {
            r.size.height = 40
        }
        if r.minX < 0 {
            r.size.width += r.origin.x
            r.origin.x = 0
        }
        if r.minY < 0 {
            r.size.height += r.origin.y
            r.origin.y = 0
        }
        if r.maxX > bounds.width {
            r.size.width = max(40, bounds.width - r.origin.x)
        }
        if r.maxY > bounds.height {
            r.size.height = max(40, bounds.height - r.origin.y)
        }
        if r.size.width < 40 || r.size.height < 40 { return self }
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
