//
//  CertificateASN1Parser.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import AltSign
import CommonCrypto
import Security

struct ASN1Item {
    let tag: UInt8
    let data: Data
}

struct CertificateBriefInfo {
    let validFrom: String
    let validUntil: String
    let type: String
}

struct ValidityStats {
    let totalDays: Int
    let elapsedDays: Int
    let remainingDays: Int
    let progress: Double
}

struct ParsedCertificateDetails {
    var version: String = "N/A"
    var subject: String = "N/A"
    var issuer: String = "N/A"
    var serialHex: String = "N/A"
    var serialDec: String = "N/A"
    var validFrom: Date? = nil
    var validUntil: Date? = nil
    var publicKeyType: String = "N/A"
    var signatureAlgorithm: String = "N/A"
    var fingerprintSHA1: String = "N/A"
    var fingerprintSHA256: String = "N/A"
}

func getDERData(from pemOrDer: Data) -> Data? {
    guard let str = String(data: pemOrDer, encoding: .ascii) else {
        return pemOrDer
    }
    
    if str.contains("-----BEGIN CERTIFICATE-----") {
        let clean = str
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: clean)
    }
    
    return pemOrDer
}

func parseASN1TLV(_ data: Data, offset: inout Int) -> ASN1Item? {
    guard offset < data.count else { return nil }
    
    let tag = data[offset]
    offset += 1
    
    guard offset < data.count else { return nil }
    var length: Int = 0
    let lenByte = data[offset]
    offset += 1
    
    if lenByte & 0x80 == 0 {
        length = Int(lenByte)
    } else {
        let numBytes = Int(lenByte & 0x7F)
        guard offset + numBytes <= data.count else { return nil }
        for _ in 0..<numBytes {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
    }
    
    guard offset + length <= data.count else { return nil }
    let valueData = data[offset..<offset+length]
    offset += length
    
    return ASN1Item(tag: tag, data: Data(valueData))
}

func getBriefInfo(for data: Data?) -> CertificateBriefInfo? {
    guard let data, let cleanDer = getDERData(from: data) else { return nil }
    
    var offset = 0
    guard let outerSeq = parseASN1TLV(cleanDer, offset: &offset), outerSeq.tag == 0x30 else { return nil }
    var tbsOffset = 0
    guard let tbsSeq = parseASN1TLV(outerSeq.data, offset: &tbsOffset), tbsSeq.tag == 0x30 else { return nil }
    
    var innerOffset = 0
    if innerOffset < tbsSeq.data.count && tbsSeq.data[innerOffset] == 0xA0 {
        _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset)
    }
    
    guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    guard let issuerItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    
    guard let validityItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    var valOffset = 0
    guard let notBeforeItem = parseASN1TLV(validityItem.data, offset: &valOffset),
          let notAfterItem = parseASN1TLV(validityItem.data, offset: &valOffset) else { return nil }
    
    let fromDate = parseDate(from: notBeforeItem)
    let untilDate = parseDate(from: notAfterItem)
    
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    
    let validFromStr = fromDate != nil ? formatter.string(from: fromDate!) : "N/A"
    let validUntilStr = untilDate != nil ? formatter.string(from: untilDate!) : "N/A"
    
    let issuerDN = parseDN(issuerItem.data)
    var typeStr = "Developer Certificate"
    
    var subjectDN = ""
    if let subjectItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) {
        subjectDN = parseDN(subjectItem.data)
    }
    
    if subjectDN.contains("Root") || issuerDN.contains("Root") {
        typeStr = "Root CA"
    } else if subjectDN.contains("Authority") || subjectDN.contains("Relations") || issuerDN.contains("Authority") {
        typeStr = "Intermediate CA"
    }
    
    return CertificateBriefInfo(validFrom: validFromStr, validUntil: validUntilStr, type: typeStr)
}

func computeValidityStats(from: Date, until: Date) -> ValidityStats {
    let totalSecs = until.timeIntervalSince(from)
    let elapsedSecs = Date().timeIntervalSince(from)
    let remainingSecs = until.timeIntervalSinceNow
    
    let totalDays = max(1, Int(totalSecs / 86400))
    let elapsedDays = max(0, Int(elapsedSecs / 86400))
    let remainingDays = max(0, Int(remainingSecs / 86400))
    
    let progress = totalSecs > 0 ? min(1.0, max(0.0, elapsedSecs / totalSecs)) : 0.0
    return ValidityStats(totalDays: totalDays, elapsedDays: elapsedDays, remainingDays: remainingDays, progress: progress)
}

func computeSHA1Fingerprint(data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
}

func computeSHA256Fingerprint(data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
}

func parseDN(_ data: Data) -> String {
    var offset = 0
    var parts: [String] = []
    
    while offset < data.count {
        guard let setItem = parseASN1TLV(data, offset: &offset), setItem.tag == 0x31 else { break }
        
        var setOffset = 0
        while setOffset < setItem.data.count {
            guard let seqItem = parseASN1TLV(setItem.data, offset: &setOffset), seqItem.tag == 0x30 else { break }
            
            var seqOffset = 0
            guard let oidItem = parseASN1TLV(seqItem.data, offset: &seqOffset), oidItem.tag == 0x06,
                  let valItem = parseASN1TLV(seqItem.data, offset: &seqOffset) else { break }
            
            let oidStr = oidItem.data.map { String($0) }.joined(separator: ".")
            let label = friendlyOIDLabel(oidStr)
            
            if let strVal = String(data: valItem.data, encoding: .utf8) {
                parts.append("\(label)=\(strVal)")
            } else if let strVal = String(data: valItem.data, encoding: .ascii) {
                parts.append("\(label)=\(strVal)")
            }
        }
    }
    return parts.joined(separator: ", ")
}

func friendlyOIDLabel(_ oid: String) -> String {
    switch oid {
    case "85.4.3": return "Common Name"
    case "85.4.6": return "Country"
    case "85.4.7": return "Locality"
    case "85.4.8": return "State"
    case "85.4.10": return "Organization"
    case "85.4.11": return "Organizational Unit"
    case "42.134.72.134.247.13.1.9.1": return "Email"
    default: return oid
    }
}

func parseDate(from item: ASN1Item) -> Date? {
    guard let str = String(data: item.data, encoding: .ascii) else { return nil }
    
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    if item.tag == 0x17 {
        formatter.dateFormat = "yyMMddHHmmssZ"
        if let date = formatter.date(from: str) {
            return date
        }
        formatter.dateFormat = "yyMMddHHmmZ"
        return formatter.date(from: str)
    } else if item.tag == 0x18 {
        formatter.dateFormat = "yyyyMMddHHmmssZ"
        return formatter.date(from: str)
    }
    return nil
}

func parsePublicKeyType(pubKeyInfoData: Data) -> String {
    var offset = 0
    guard let algSeq = parseASN1TLV(pubKeyInfoData, offset: &offset), algSeq.tag == 0x30 else { return "RSA" }
    var algOffset = 0
    guard let oidItem = parseASN1TLV(algSeq.data, offset: &algOffset), oidItem.tag == 0x06 else { return "RSA" }
    
    let oidStr = oidItem.data.map { String($0) }.joined(separator: ".")
    if oidStr == "42.134.72.134.247.13.1.1.1" {
        return "RSA"
    } else if oidStr == "42.134.72.206.61.2.1" {
        return "EC"
    }
    return "RSA"
}

func parseSignatureAlgorithm(_ oidData: Data) -> String {
    let oidStr = oidData.map { String($0) }.joined(separator: ".")
    switch oidStr {
    case "42.134.72.134.247.13.1.1.11": return "SHA-256 with RSA"
    case "42.134.72.134.247.13.1.1.5": return "SHA-1 with RSA"
    case "42.134.72.206.61.4.3.2": return "ECDSA with SHA-256"
    default: return "SHA-256 with RSA"
    }
}

func parseCertificate(derData: Data) -> ParsedCertificateDetails {
    var details = ParsedCertificateDetails()
    guard let cleanDer = getDERData(from: derData) else { return details }
    details.fingerprintSHA1 = computeSHA1Fingerprint(data: cleanDer)
    details.fingerprintSHA256 = computeSHA256Fingerprint(data: cleanDer)
    
    var offset = 0
    guard let outerSeq = parseASN1TLV(cleanDer, offset: &offset), outerSeq.tag == 0x30 else { return details }
    var tbsOffset = 0
    guard let tbsSeq = parseASN1TLV(outerSeq.data, offset: &tbsOffset), tbsSeq.tag == 0x30 else { return details }
    
    var innerOffset = 0
    var versionVal = 1
    if innerOffset < tbsSeq.data.count && tbsSeq.data[innerOffset] == 0xA0 {
        if let taggedVersion = parseASN1TLV(tbsSeq.data, offset: &innerOffset) {
            var verOffset = 0
            if let verInt = parseASN1TLV(taggedVersion.data, offset: &verOffset), verInt.tag == 0x02 {
                if verInt.data.count == 1 {
                    versionVal = Int(verInt.data[0]) + 1
                }
            }
        }
    }
    details.version = String(versionVal)
    
    if let serialItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), serialItem.tag == 0x02 {
        details.serialHex = "0x" + serialItem.data.map { String(format: "%02X", $0) }.joined()
        var decVal: UInt64 = 0
        for byte in serialItem.data {
            decVal = (decVal << 8) | UInt64(byte)
        }
        details.serialDec = String(decVal)
    }
    
    if let sigAlgItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), sigAlgItem.tag == 0x30 {
        var sigOffset = 0
        if let sigOidItem = parseASN1TLV(sigAlgItem.data, offset: &sigOffset), sigOidItem.tag == 0x06 {
            details.signatureAlgorithm = parseSignatureAlgorithm(sigOidItem.data)
        }
    }
    
    if let issuerItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), issuerItem.tag == 0x30 {
        details.issuer = parseDN(issuerItem.data)
    }
    
    if let validityItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), validityItem.tag == 0x30 {
        var valOffset = 0
        if let notBeforeItem = parseASN1TLV(validityItem.data, offset: &valOffset),
           let notAfterItem = parseASN1TLV(validityItem.data, offset: &valOffset) {
            details.validFrom = parseDate(from: notBeforeItem)
            details.validUntil = parseDate(from: notAfterItem)
        }
    }
    
    if let subjectItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), subjectItem.tag == 0x30 {
        details.subject = parseDN(subjectItem.data)
    }
    
    if let pubKeyInfoItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), pubKeyInfoItem.tag == 0x30 {
        details.publicKeyType = parsePublicKeyType(pubKeyInfoData: pubKeyInfoItem.data)
    }
    
    return details
}

extension ALTCertificate {
    var creationDate: Date {
        guard let data = self.data,
              let cleanDer = getDERData(from: data) else {
            return Date.distantPast
        }
        var offset = 0
        guard let outerSeq = parseASN1TLV(cleanDer, offset: &offset), outerSeq.tag == 0x30 else { return Date.distantPast }
        var tbsOffset = 0
        guard let tbsSeq = parseASN1TLV(outerSeq.data, offset: &tbsOffset), tbsSeq.tag == 0x30 else { return Date.distantPast }
        
        var innerOffset = 0
        if innerOffset < tbsSeq.data.count && tbsSeq.data[innerOffset] == 0xA0 {
            _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset)
        }
        
        guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        
        guard let validityItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        var valOffset = 0
        guard let notBeforeItem = parseASN1TLV(validityItem.data, offset: &valOffset) else { return Date.distantPast }
        
        return parseDate(from: notBeforeItem) ?? Date.distantPast
    }
}
