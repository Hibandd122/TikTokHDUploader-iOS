//
//  CRC32.swift
//  TikTokUploader iOS
//

import Foundation

public struct CRC32 {
    private static let table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    public static func checksum(data: Data) -> String {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        let finalCrc = crc ^ 0xFFFFFFFF
        return String(format: "%08x", finalCrc).lowercased()
    }
}
