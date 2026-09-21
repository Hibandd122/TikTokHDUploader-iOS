//
//  XBogus.swift
//  TikTokUploader iOS
//
//  Native Swift implementation of ByteDance / TikTok Web X-Bogus signing algorithm.
//

import Foundation
import CryptoKit

public struct XBogus {
    private static let hexMap: [UInt8: UInt8] = [
        48: 0, 49: 1, 50: 2, 51: 3, 52: 4, 53: 5,
        54: 6, 55: 7, 56: 8, 57: 9, 97: 10, 98: 11,
        99: 12, 100: 13, 101: 14, 102: 15
    ]

    private static func md5String(_ str: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(str.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func md5Bytes(_ bytes: [UInt8]) -> String {
        let digest = Insecure.MD5.hash(data: Data(bytes))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeHexStr(_ str: String) -> [UInt8] {
        let utf8 = Array(str.utf8)
        var result = [UInt8]()
        var i = 0
        while i + 1 < utf8.count && i < 32 {
            let h1 = hexMap[utf8[i]] ?? 0
            let h2 = hexMap[utf8[i + 1]] ?? 0
            result.append((h1 << 4) | h2)
            i += 2
        }
        return result
    }

    private static func encodeWithKey(key: [UInt8], data: [UInt8]) -> [UInt8] {
        var sBox = Array(0..<256).map { UInt8($0) }
        var temp: Int = 0
        let keyCount = key.count

        for i in 0..<256 {
            temp = (temp + Int(sBox[i]) + Int(key[i % keyCount])) % 256
            sBox.swapAt(i, temp)
        }

        var t2 = 0
        var t1 = 0
        var output = [UInt8]()
        for byte in data {
            t2 = (t2 + 1) % 256
            t1 = (t1 + Int(sBox[t2])) % 256
            sBox.swapAt(t2, t1)
            let sIdx = (Int(sBox[t2]) + Int(sBox[t1])) % 256
            output.append(byte ^ sBox[sIdx])
        }
        return output
    }

    private static func b64Encode(bytes: [UInt8], keyTable: String) -> String {
        let table = Array(keyTable)
        var output = ""
        var i = 0
        while i < bytes.count {
            let b0 = Int(bytes[i])
            let b1 = (i + 1 < bytes.count) ? Int(bytes[i + 1]) : -1
            let b2 = (i + 2 < bytes.count) ? Int(bytes[i + 2]) : -1

            let a1 = b0 >> 2
            let a2 = ((3 & b0) << 4) | (b1 >= 0 ? (b1 >> 4) : 0)
            let a3 = (b1 >= 0) ? (((15 & b1) << 2) | (b2 >= 0 ? (b2 >> 6) : 0)) : 64
            let a4 = (b2 >= 0) ? (63 & b2) : 64

            output.append(table[a1])
            output.append(table[a2])
            if a3 < table.count { output.append(table[a3]) }
            if a4 < table.count { output.append(table[a4]) }
            i += 3
        }
        return output
    }

    private static func scrambleOrder(_ args: [Int]) -> [UInt8] {
        var res = Array(repeating: UInt8(0), count: 19)
        guard args.count >= 19 else { return res }
        res[0] = UInt8(args[0])
        res[1] = UInt8(args[10])
        res[2] = UInt8(args[1])
        res[3] = UInt8(args[11])
        res[4] = UInt8(args[2])
        res[5] = UInt8(args[12])
        res[6] = UInt8(args[3])
        res[7] = UInt8(args[13])
        res[8] = UInt8(args[4])
        res[9] = UInt8(args[14])
        res[10] = UInt8(args[5])
        res[11] = UInt8(args[15])
        res[12] = UInt8(args[6])
        res[13] = UInt8(args[16])
        res[14] = UInt8(args[7])
        res[15] = UInt8(args[17])
        res[16] = UInt8(args[8])
        res[17] = UInt8(args[18])
        res[18] = UInt8(args[9])
        return res
    }

    public static func sign(params: String, postData: String, userAgent: String) -> String {
        let s0 = md5String(postData)
        let s1 = md5String(params)
        let s0_1 = md5Bytes(decodeHexStr(s0))
        let s1_1 = md5Bytes(decodeHexStr(s1))

        let d = encodeWithKey(key: [0, 1, 12], data: Array(userAgent.utf8))
        let uaB64 = b64Encode(bytes: d, keyTable: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        let uaMd5 = md5String(uaB64)

        let timestamp = Int(Date().timeIntervalSince1970)
        let canvas = 536919696

        let decS1 = decodeHexStr(s1_1)
        let decS0 = decodeHexStr(s0_1)
        let decUa = decodeHexStr(uaMd5)

        var saltList: [Int] = [
            timestamp,
            canvas,
            64, 0, 1, 12,
            Int(decS1[decS1.count - 2]),
            Int(decS1[decS1.count - 1]),
            Int(decS0[decS0.count - 2]),
            Int(decS0[decS0.count - 1]),
            Int(decUa[decUa.count - 2]),
            Int(decUa[decUa.count - 1])
        ]

        for shift in [24, 16, 8, 0] { saltList.append((saltList[0] >> shift) & 255) }
        for shift in [24, 16, 8, 0] { saltList.append((saltList[1] >> shift) & 255) }

        var xorSum = 64
        for x in saltList[3...] { xorSum ^= x }
        saltList.append(xorSum)
        saltList.append(255)

        // Permute indices: [3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 4, 6, 8, 10, 12, 14, 16, 18, 20]
        let permuteIndices = [3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 4, 6, 8, 10, 12, 14, 16, 18, 20]
        var numList = [Int]()
        for idx in permuteIndices { numList.append(saltList[idx - 1]) }

        let scrambled = scrambleOrder(numList)
        let short2 = encodeWithKey(key: [255], data: scrambled)

        var short3: [UInt8] = [2, 255]
        short3.append(contentsOf: short2)

        let customB64Table = "Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe"
        return b64Encode(bytes: short3, keyTable: customB64Table)
    }
}
