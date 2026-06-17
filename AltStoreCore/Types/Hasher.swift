//
//  Hasher.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import Foundation
import CryptoKit

@objc(RSTHasher)
public final class RSTHasher: NSObject {
    private override init() {}
    
    @objc(sha1HashOfFileAtURL:error:)
    public static func sha1HashOfFile(at url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }
        
        var sha1 = Insecure.SHA1()
        let bufferSize = 1024 * 1024
        
        while true {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty {
                break
            }
            sha1.update(data: data)
        }
        
        let digest = sha1.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    @objc(sha1HashOfData:)
    public static func sha1Hash(of data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
