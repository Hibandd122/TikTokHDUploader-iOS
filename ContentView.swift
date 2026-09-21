//
//  ContentView.swift
//  TikTokUploader iOS
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var engine = TikTokUploaderEngine()
    @AppStorage("tiktok_session_id") private var storedSessionId: String = ""

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideoUrl: URL?
    @State private var videoTitle: String = ""
    @State private var tagInput: String = ""
    @State private var hashtags: [String] = ["fyp", "anime", "edit", "viral"]
    @State private var visibilityType: Int = 0 // 0: Public, 1: Friends, 2: Private

    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var isShowingSessionSheet: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Video Selection Card
                        VStack(spacing: 12) {
                            if let selectedVideoUrl = selectedVideoUrl {
                                HStack {
                                    Image(systemName: "video.fill")
                                        .font(.title)
                                        .foregroundColor(.cyan)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(selectedVideoUrl.lastPathComponent)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text("Sẵn sàng đăng chuẩn Full HD")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                    Spacer()
                                    PhotosPicker(selection: $selectedItem, matching: .videos) {
                                        Text("Đổi")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.cyan)
                                    }
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(16)
                            } else {
                                PhotosPicker(selection: $selectedItem, matching: .videos) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "arrow.up.circle.badge.plus")
                                            .font(.system(size: 40))
                                            .foregroundColor(.cyan)
                                        Text("Chọn Video từ Thư Viện")
                                            .font(.headline)
                                        Text("Hỗ trợ chuẩn 100% Full HD (Không nén)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 120)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(Color.cyan.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)

                        // 2. Caption Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tiêu đề / Caption")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)

                            TextField("Nhập nội dung video...", text: $videoTitle)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        // 3. Hashtags Builder
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Hashtags (\(hashtags.count) thẻ)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Không giới hạn")
                                    .font(.caption)
                                    .foregroundColor(.cyan)
                            }

                            HStack {
                                TextField("Thêm thẻ (vd: foryou, 4k)...", text: $tagInput)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(10)

                                Button(action: addTag) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.cyan)
                                }
                            }

                            // Tags chips flow
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(hashtags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text("#\(tag)")
                                                .font(.caption.bold())
                                            Button(action: { removeTag(tag) }) {
                                                Image(systemName: "xmark")
                                                    .font(.caption2)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.cyan.opacity(0.15))
                                        .foregroundColor(.cyan)
                                        .cornerRadius(20)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        // 4. Privacy & Account
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Chế độ đăng")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Picker("Quyền riêng tư", selection: $visibilityType) {
                                    Text("Công khai").tag(0)
                                    Text("Bạn bè").tag(1)
                                    Text("Riêng tư").tag(2)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }

                            Button(action: { isShowingSessionSheet = true }) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                        .foregroundColor(storedSessionId.isEmpty ? .orange : .green)
                                    Text(storedSessionId.isEmpty ? "Chưa cài Cookie sessionid" : "Đã lưu sessionid")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("Cài đặt")
                                        .font(.caption.bold())
                                        .foregroundColor(.cyan)
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)

                        // 5. Progress & Action Button
                        VStack(spacing: 12) {
                            if engine.isUploading {
                                VStack(spacing: 6) {
                                    ProgressView(value: engine.uploadProgress, total: 1.0)
                                        .tint(.cyan)
                                    Text(engine.statusMessage)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                            }

                            Button(action: startUpload) {
                                HStack {
                                    if engine.isUploading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                    }
                                    Text(engine.isUploading ? "Đang xử lý..." : "Đăng Ngay (Full Request HD)")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(canUpload ? Color.cyan : Color.gray.opacity(0.4))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .shadow(color: canUpload ? Color.cyan.opacity(0.4) : .clear, radius: 10, y: 5)
                            }
                            .disabled(!canUpload)
                            .padding(.horizontal)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("TikTok HD Uploader")
            .onChange(of: selectedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("upload_input.mp4")
                        try? data.write(to: tempUrl)
                        await MainActor.run {
                            self.selectedVideoUrl = tempUrl
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingSessionSheet) {
                SessionIdConfigView(sessionId: $storedSessionId)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Thông Báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var canUpload: Bool {
        return selectedVideoUrl != nil && !storedSessionId.isEmpty && !engine.isUploading
    }

    private func addTag() {
        let clean = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty && !hashtags.contains(clean) {
            hashtags.append(clean)
            tagInput = ""
        }
    }

    private func removeTag(_ tag: String) {
        hashtags.removeAll { $0 == tag }
    }

    private func startUpload() {
        guard let url = selectedVideoUrl else { return }
        engine.uploadAndPublish(
            videoUrl: url,
            title: videoTitle,
            tags: hashtags,
            sessionId: storedSessionId,
            visibilityType: visibilityType
        ) { success, msg in
            alertMessage = msg
            showAlert = true
        }
    }
}

struct SessionIdConfigView: View {
    @Binding var sessionId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dán Cookie `sessionid` tài khoản TikTok của bạn vào đây. App sẽ lưu trữ an toàn trong máy:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: $sessionId)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)

                Text("Cách lấy: Đăng nhập tiktok.com trên Safari/Chrome máy tính -> F12 -> Application -> Cookies -> sessionid.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Cấu Hình Session ID")
            .navigationBarItems(trailing: Button("Xong") { dismiss() })
        }
    }
}
