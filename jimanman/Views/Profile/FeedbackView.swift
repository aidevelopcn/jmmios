import SwiftUI
import UIKit

/// 问题反馈（对齐 Android FeedbackScreen）
struct FeedbackView: View {
    var onBack: () -> Void

    private let maxImages = 3
    private let maxLength = 500

    @State private var content = ""
    @State private var contact = ""
    @State private var images: [String] = []
    @State private var uploading = false
    @State private var submitting = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var showPicker = false
    @State private var pickedImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ProfileSimpleTopBar(title: "问题反馈", onBack: onBack)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    descriptionCard
                    screenshotCard
                    contactCard
                    submitButton
                    Spacer().frame(height: 24)
                }
                .padding(14)
            }
        }
        .background(Color(hex: "F5F7FA").ignoresSafeArea())
        .modifier(KeyboardBottomPadding())
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
        }
        .onChange(of: pickedImage) { image in
            guard let image else { return }
            pickedImage = nil
            uploadScreenshot(image)
        }
        .alert("提示", isPresented: $showToast) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(toastMessage)
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("问题描述").font(.system(size: 15, weight: .medium)).foregroundColor(Color(hex: "111111"))
                Text(" *").font(.system(size: 15)).foregroundColor(Color(hex: "F43F5E"))
            }
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("请描述你遇到的问题，比如在哪个页面、做了什么操作、出现了什么现象")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "999999"))
                        .padding(.top, 12)
                        .padding(.horizontal, 12)
                }
                TextEditor(text: $content)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "333333"))
                    .frame(height: 150)
                    .padding(8)
                    .opacity(content.isEmpty ? 0.85 : 1)
                    .onChange(of: content) { value in
                        if value.count > maxLength {
                            content = String(value.prefix(maxLength))
                        }
                    }
            }
            .background(Color(hex: "F8F8F8"))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "D1D5DB"), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("\(content.count)/\(maxLength)")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "999999"))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("截图（选填）").font(.system(size: 15, weight: .medium)).foregroundColor(Color(hex: "111111"))
            Text("最多 \(maxImages) 张，有问题页面截图更容易定位")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "999999"))
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color(hex: "F3F4F6")
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            images.remove(at: index)
                        } label: {
                            Text("×")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.black.opacity(0.66))
                                .clipShape(Circle())
                        }
                        .padding(3)
                    }
                }
                if images.count < maxImages {
                    Button {
                        if !uploading { showPicker = true }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "F8F8F8"))
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
                            if uploading {
                                ProgressView().tint(Color(hex: "00AFA4"))
                            } else {
                                Text("+").font(.system(size: 26)).foregroundColor(Color(hex: "999999"))
                            }
                        }
                        .frame(width: 80, height: 80)
                    }
                    .buttonStyle(.plain)
                    .disabled(uploading)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("联系方式").font(.system(size: 15, weight: .medium)).foregroundColor(Color(hex: "111111"))
                Text("（选填）").font(.system(size: 12)).foregroundColor(Color(hex: "999999"))
            }
            TextField("手机号 / 微信 / QQ，方便我们联系你", text: $contact)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color(hex: "F8F8F8"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "D1D5DB"), lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: contact) { value in
                    if value.count > 100 { contact = String(value.prefix(100)) }
                }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(submitting ? "提交中…" : "提交反馈")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule().fill(submitting || uploading ? Color(hex: "9AE6E1") : Color(hex: "00AFA4"))
                )
        }
        .buttonStyle(.plain)
        .disabled(submitting || uploading)
        .padding(.top, 8)
    }

    private func uploadScreenshot(_ image: UIImage) {
        guard images.count < maxImages else {
            toast("最多上传 \(maxImages) 张截图")
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        uploading = true
        Task {
            let url = await ApiService.shared.uploadFile(imageData: data, fileName: "feedback.jpg", mimeType: "image/jpeg")
            await MainActor.run {
                uploading = false
                if let url, !url.isEmpty {
                    images.append(url)
                } else {
                    toast("截图上传失败，请重试")
                }
            }
        }
    }

    private func submit() {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count < 5 {
            toast("请至少填写 5 个字的问题描述")
            return
        }
        if (ApiService.shared.token ?? "").isEmpty {
            toast("请先登录")
            return
        }
        submitting = true
        Task {
            let ok = await ApiService.shared.submitFeedback(
                content: text,
                contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
                images: images
            )
            await MainActor.run {
                submitting = false
                if ok {
                    toast("反馈已提交，感谢你的反馈")
                    onBack()
                } else {
                    toast("提交失败，请稍后重试")
                }
            }
        }
    }

    private func toast(_ message: String) {
        toastMessage = message
        showToast = true
    }
}
