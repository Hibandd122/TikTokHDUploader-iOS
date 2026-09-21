//
//  AWSSigV4.swift
//  TikTokUploader iOS
//

import Foundation
import CryptoKit

public struct AWSSigV4 {
    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func getSignatureKey(secretKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kSecret = Data(("AWS4" + secretKey).utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    public static func calculateSignature(
        accessKey: String,
        secretKey: String,
        requestParams: String,
        headers: [String: String],
        method: String = "GET",
        payload: String = "",
        region: String = "ap-singapore-1",
        service: String = "vod"
    ) -> String {
        let canonicalUri = "/"
        let canonicalQuerystring = requestParams

        let sortedKeys = headers.keys.map { $0.lowercased() }.sorted()
        let canonicalHeaders = sortedKeys.map { "\($0):\(headers[$0] ?? headers[$0.capitalized] ?? "")" }.joined(separator: "\n") + "\n"
        let signedHeaders = sortedKeys.joined(separator: ";")
        let payloadHash = sha256Hex(payload)

        let canonicalRequest = "\(method)\n\(canonicalUri)\n\(canonicalQuerystring)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        
        let amzDate = headers["x-amz-date"] ?? headers["X-Amz-Date"] ?? ""
        let dateStamp = String(amzDate.split(separator: "T").first ?? "")

        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "\(algorithm)\n\(amzDate)\n\(credentialScope)\n\(sha256Hex(canonicalRequest))"

        let signingKey = getSignatureKey(secretKey: secretKey, dateStamp: dateStamp, region: region, service: service)
        let signatureData = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
        return signatureData.map { String(format: "%02x", $0) }.joined()
    }
}
