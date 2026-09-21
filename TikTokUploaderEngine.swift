//
//  TikTokUploaderEngine.swift
//  TikTokUploader iOS
//

import Foundation

public struct TagItem: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public init(_ name: String) {
        self.name = name.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public class TikTokUploaderEngine: ObservableObject {
    @Published public var uploadProgress: Double = 0.0
    @Published public var statusMessage: String = "Sẵn sàng"
    @Published public var isUploading: Bool = false

    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private let urlPrefix = "www"

    public init() {}

    public func uploadAndPublish(
        videoUrl: URL,
        title: String,
        tags: [String],
        sessionId: String,
        visibilityType: Int = 0,
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isUploading = true
                self.uploadProgress = 0.05
                self.statusMessage = "Đang kiểm tra xác thực tài khoản..."
            }

            // 1. Verify Auth
            guard let videoData = try? Data(contentsOf: videoUrl) else {
                self.finish(false, "Không thể đọc dữ liệu video từ thư viện", completion)
                return
            }

            let session = URLSession.shared
            var authReq = URLRequest(url: URL(string: "https://\(self.urlPrefix).tiktok.com/passport/web/account/info/")!)
            authReq.setValue("sessionid=\(sessionId)", forHTTPHeaderField: "Cookie")
            authReq.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")

            let authSemaphore = DispatchSemaphore(value: 0)
            var authedUsername = ""
            var authOk = false

            session.dataTask(with: authReq) { data, resp, err in
                defer { authSemaphore.signal() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let d = json["data"] as? [String: Any],
                      let _ = d["user_id_str"] else { return }
                authedUsername = (d["username"] as? String) ?? "User"
                authOk = true
            }.resume()
            authSemaphore.wait()

            guard authOk else {
                self.finish(false, "Cookie sessionid không hợp lệ hoặc đã hết hạn", completion)
                return
            }

            DispatchQueue.main.async {
                self.uploadProgress = 0.15
                self.statusMessage = "Đã xác thực @\(authedUsername). Đang lấy token VOD..."
            }

            // 2. Fetch VOD Token
            var vodTokenReq = URLRequest(url: URL(string: "https://www.tiktok.com/api/v1/video/upload/auth/")!)
            vodTokenReq.setValue("sessionid=\(sessionId)", forHTTPHeaderField: "Cookie")
            vodTokenReq.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")

            var accessKey = "", secretKey = "", sessionToken = ""
            let tokenSem = DispatchSemaphore(value: 0)

            session.dataTask(with: vodTokenReq) { data, _, _ in
                defer { tokenSem.signal() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let v5 = json["video_token_v5"] as? [String: Any] else { return }
                accessKey = v5["access_key_id"] as? String ?? ""
                secretKey = v5["secret_acess_key"] as? String ?? ""
                sessionToken = v5["session_token"] as? String ?? ""
            }.resume()
            tokenSem.wait()

            guard !accessKey.isEmpty else {
                self.finish(false, "Không lấy được quyền VOD từ ByteDance Cloud", completion)
                return
            }

            // 3. Apply Upload Inner Address
            let fileSize = videoData.count
            let topParams = "Action=ApplyUploadInner&Version=2020-11-19&SpaceName=tiktok&FileType=video&IsInner=1&FileSize=\(fileSize)&s=g158iqx8434"
            let topUrl = URL(string: "https://www.tiktok.com/top/v1?\(topParams)")!

            let now = Date()
            let isoFormatter = DateFormatter()
            isoFormatter.locale = Locale(identifier: "en_US_POSIX")
            isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            isoFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            let amzDate = isoFormatter.string(from: now)

            let dateStampFormatter = DateFormatter()
            dateStampFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateStampFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateStampFormatter.dateFormat = "yyyyMMdd"
            let dateStamp = dateStampFormatter.string(from: now)

            var topHeaders: [String: String] = [
                "x-amz-date": amzDate,
                "x-amz-security-token": sessionToken
            ]
            let sig = AWSSigV4.calculateSignature(
                accessKey: accessKey,
                secretKey: secretKey,
                requestParams: topParams,
                headers: topHeaders,
                method: "GET",
                payload: ""
            )
            let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(dateStamp)/ap-singapore-1/vod/aws4_request, SignedHeaders=x-amz-date;x-amz-security-token, Signature=\(sig)"

            var applyReq = URLRequest(url: topUrl)
            applyReq.setValue(authHeader, forHTTPHeaderField: "Authorization")
            applyReq.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
            applyReq.setValue(sessionToken, forHTTPHeaderField: "x-amz-security-token")
            applyReq.setValue("sessionid=\(sessionId)", forHTTPHeaderField: "Cookie")

            var uploadHost = "", storeUri = "", videoAuth = "", sessionKey = "", videoId = ""
            let applySem = DispatchSemaphore(value: 0)

            session.dataTask(with: applyReq) { data, _, _ in
                defer { applySem.signal() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["Result"] as? [String: Any],
                      let inner = result["InnerUploadAddress"] as? [String: Any],
                      let nodes = inner["UploadNodes"] as? [[String: Any]],
                      let first = nodes.first else { return }

                videoId = first["Vid"] as? String ?? ""
                uploadHost = first["UploadHost"] as? String ?? ""
                sessionKey = first["SessionKey"] as? String ?? ""
                if let storeInfos = first["StoreInfos"] as? [[String: Any]], let si = storeInfos.first {
                    storeUri = si["StoreUri"] as? String ?? ""
                    videoAuth = si["Auth"] as? String ?? ""
                }
            }.resume()
            applySem.wait()

            guard !uploadHost.isEmpty && !videoId.isEmpty else {
                self.finish(false, "ByteDance Cloud không cấp địa chỉ tải lên", completion)
                return
            }

            // 4. Init Multipart Upload
            let boundary = "---------------------------" + String(Int.random(in: 100000000000...999999999999))
            var initReq = URLRequest(url: URL(string: "https://\(uploadHost)/\(storeUri)?uploads")!)
            initReq.httpMethod = "POST"
            initReq.setValue(videoAuth, forHTTPHeaderField: "Authorization")
            initReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            initReq.httpBody = "--\(boundary)--".data(using: .utf8)

            var uploadId = ""
            let initSem = DispatchSemaphore(value: 0)
            session.dataTask(with: initReq) { data, _, _ in
                defer { initSem.signal() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = json["payload"] as? [String: Any] else { return }
                uploadId = payload["uploadID"] as? String ?? ""
            }.resume()
            initSem.wait()

            guard !uploadId.isEmpty else {
                self.finish(false, "Khởi tạo khối dữ liệu VOD thất bại", completion)
                return
            }

            // 5. Upload 5MB Chunks
            let chunkSize = 5242880
            let totalChunks = (fileSize + chunkSize - 1) / chunkSize
            var crcList = [String]()

            for i in 0..<totalChunks {
                let start = i * chunkSize
                let end = min(start + chunkSize, fileSize)
                let chunkData = videoData.subdata(in: start..<end)
                let crc = CRC32.checksum(data: chunkData)
                crcList.append(crc)

                let partUrl = URL(string: "https://\(uploadHost)/\(storeUri)?partNumber=\(i + 1)&uploadID=\(uploadId)")!
                var partReq = URLRequest(url: partUrl)
                partReq.httpMethod = "POST"
                partReq.setValue(videoAuth, forHTTPHeaderField: "Authorization")
                partReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                partReq.setValue(crc, forHTTPHeaderField: "Content-Crc32")
                partReq.httpBody = chunkData

                var partOk = false
                let partSem = DispatchSemaphore(value: 0)
                session.dataTask(with: partReq) { _, resp, _ in
                    defer { partSem.signal() }
                    if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                        partOk = true
                    }
                }.resume()
                partSem.wait()

                guard partOk else {
                    self.finish(false, "Lỗi tải khối dữ liệu \(i + 1)/\(totalChunks)", completion)
                    return
                }

                let progress = 0.25 + (Double(i + 1) / Double(totalChunks)) * 0.55
                DispatchQueue.main.async {
                    self.uploadProgress = progress
                    self.statusMessage = "Đang tải dữ liệu HD: \(Int(progress * 100))% (Khối \(i + 1)/\(totalChunks))"
                }
            }

            // 6. Complete Parts
            let completeUrl = URL(string: "https://\(uploadHost)/\(storeUri)?uploadID=\(uploadId)")!
            var completeReq = URLRequest(url: completeUrl)
            completeReq.httpMethod = "POST"
            completeReq.setValue(videoAuth, forHTTPHeaderField: "Authorization")
            completeReq.setValue("https://www.tiktok.com", forHTTPHeaderField: "Origin")
            completeReq.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            let partsBody = crcList.enumerated().map { "\($0.offset + 1):\($0.element)" }.joined(separator: ",")
            completeReq.httpBody = partsBody.data(using: .utf8)

            let compSem = DispatchSemaphore(value: 0)
            session.dataTask(with: completeReq) { _, _, _ in compSem.signal() }.resume()
            compSem.wait()

            // 7. Commit Upload Inner
            let commitParams = "Action=CommitUploadInner&SpaceName=tiktok&Version=2020-11-19"
            let commitUrl = URL(string: "https://vod-ap-singapore-1.bytevcloudapi.com/?\(commitParams)")!
            let commitBody = "{\"SessionKey\":\"\(sessionKey)\",\"Functions\":[]}"
            let bodyHash = SHA256.hash(data: Data(commitBody.utf8)).map { String(format: "%02x", $0) }.joined()

            let commitAmzDate = isoFormatter.string(from: Date())
            let commitDateStamp = dateStampFormatter.string(from: Date())

            var commitHeaders: [String: String] = [
                "content-type": "text/plain;charset=UTF-8",
                "x-amz-content-sha256": bodyHash,
                "x-amz-date": commitAmzDate,
                "x-amz-security-token": sessionToken
            ]
            let commitSig = AWSSigV4.calculateSignature(
                accessKey: accessKey,
                secretKey: secretKey,
                requestParams: commitParams,
                headers: commitHeaders,
                method: "POST",
                payload: commitBody
            )
            let commitAuth = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(commitDateStamp)/ap-singapore-1/vod/aws4_request, SignedHeaders=content-type;x-amz-content-sha256;x-amz-date;x-amz-security-token, Signature=\(commitSig)"

            var commitReq = URLRequest(url: commitUrl)
            commitReq.httpMethod = "POST"
            commitReq.setValue(commitAuth, forHTTPHeaderField: "authorization")
            commitReq.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            commitReq.setValue(bodyHash, forHTTPHeaderField: "x-amz-content-sha256")
            commitReq.setValue(commitAmzDate, forHTTPHeaderField: "x-amz-date")
            commitReq.setValue(sessionToken, forHTTPHeaderField: "x-amz-security-token")
            commitReq.httpBody = commitBody.data(using: .utf8)

            let commitSem = DispatchSemaphore(value: 0)
            session.dataTask(with: commitReq) { _, _, _ in commitSem.signal() }.resume()
            commitSem.wait()

            DispatchQueue.main.async {
                self.uploadProgress = 0.90
                self.statusMessage = "Đang ký số X-Bogus và đăng video..."
            }

            // 8. Publish via Web Project API with X-Bogus
            self.publishPost(videoId: videoId, title: title, tags: tags, sessionId: sessionId, visibilityType: visibilityType, completion: completion)
        }
    }

    private func publishPost(
        videoId: String,
        title: String,
        tags: [String],
        sessionId: String,
        visibilityType: Int,
        completion: @escaping (Bool, String) -> Void
    ) {
        let creationId = String((0..<21).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })

        var caption = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var textExtra: [[String: Any]] = []

        for tag in tags {
            let clean = tag.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let prefix = caption.isEmpty ? "" : " "
            let start = caption.count + prefix.count
            caption += "\(prefix)#\(clean)"
            let end = caption.count
            textExtra.append([
                "start": start,
                "end": end,
                "user_id": "",
                "type": 1,
                "hashtag_name": clean
            ])
        }

        let postQuery = "app_name=tiktok_web&channel=tiktok_web&device_platform=web&aid=1988"
        let postData: [String: Any] = [
            "cloud_edit_is_use_video_canvas": false,
            "enter_post_page_from": 1,
            "post_common_info": [
                "creation_id": creationId,
                "enter_post_page_from": 1,
                "post_type": 0
            ],
            "feature_common_info_list": [
                [
                    "geofencing_regions": [],
                    "playlist_name": "",
                    "playlist_id": "",
                    "tcm_params": "{\"commerce_toggle_info\":{}}",
                    "sound_exemption": 0,
                    "anchors": [],
                    "vedit_common_info": [
                        "video_id": videoId,
                        "application": 0
                    ],
                    "privacy_setting_info": [
                        "visibility_type": visibilityType,
                        "allow_duet": 1,
                        "allow_stitch": 1,
                        "allow_comment": 1
                    ]
                ]
            ],
            "single_post_req_list": [
                [
                    "batch_index": 0,
                    "video_id": videoId,
                    "is_long_video": 0,
                    "single_post_feature_info": [
                        "text": caption,
                        "text_extra": textExtra,
                        "markup_text": caption,
                        "music_info": [:],
                        "poster_delay": 0.0,
                        "cloud_edit_is_use_video_canvas": false,
                        "has_original_audio": 1
                    ]
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: postData, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            self.finish(false, "Không thể đóng gói JSON đăng bài", completion)
            return
        }

        let xBogus = XBogus.sign(params: postQuery, postData: jsonString, userAgent: self.userAgent)
        let publishUrl = URL(string: "https://\(self.urlPrefix).tiktok.com/tiktok/web/project/post/v1/?\(postQuery)&X-Bogus=\(xBogus)")!

        var pubReq = URLRequest(url: publishUrl)
        pubReq.httpMethod = "POST"
        pubReq.setValue("sessionid=\(sessionId)", forHTTPHeaderField: "Cookie")
        pubReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pubReq.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        pubReq.setValue("https://www.tiktok.com", forHTTPHeaderField: "Origin")
        pubReq.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        pubReq.httpBody = jsonData

        URLSession.shared.dataTask(with: pubReq) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["status_code"] as? Int, code == 0 else {
                self.finish(false, "Đăng bài thất bại từ máy chủ TikTok", completion)
                return
            }

            DispatchQueue.main.async {
                self.uploadProgress = 1.0
                self.statusMessage = "Đăng thành công! (Chuẩn Full HD)"
                self.isUploading = false
                completion(true, "Video đã được đăng thành công lên TikTok!")
            }
        }.resume()
    }

    private func finish(_ success: Bool, _ msg: String, _ completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.main.async {
            self.isUploading = false
            self.statusMessage = success ? "Hoàn tất" : "Lỗi: \(msg)"
            completion(success, msg)
        }
    }
}
