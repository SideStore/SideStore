//
//  MachOResourceViewer.swift
//  SideStore
//
//  Created by Magesh K on 3/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign
import CodeSignKit

struct MachOResourceViewer: View {
    let url: URL

    @State private var parser: MachOParser? = nil
    @State private var dumpText: String = ""
    @State private var isLoaded = false
    @State private var showingShareSheet = false

    var body: some View {
        List {
            if let parser = parser {
                Section(header: Text("Binary Summary")) {
                    InfoRow(label: "Name", value: url.lastPathComponent)
                    InfoRow(label: "Path", value: url.path)
                    InfoRow(label: "Size", value: formatSize(url))

                    let archs = parser.architectures()
                    InfoRow(label: "Architectures", value: archs.isEmpty ? NSLocalizedString("Unknown", comment: "") : archs.joined(separator: ", "))

                    if let platform = parser.platformType() {
                        InfoRow(label: "Platform", value: platform)
                    }

                    if let minOS = parser.minimumOSVersion() {
                        InfoRow(label: "Min OS Version", value: minOS)
                    }

                    InfoRow(
                        label: "Encrypted (DRM)",
                        value: parser.isEncrypted() ? NSLocalizedString("Yes", comment: "") : NSLocalizedString("No", comment: ""),
                        valueColor: parser.isEncrypted() ? .orange : .green
                    )

                    if let bundleID = parser.bundleIdentifier() {
                        InfoRow(label: "Bundle ID", value: bundleID)
                    }

                    if let teamID = parser.teamID() {
                        InfoRow(label: "Team ID", value: teamID)
                    }

                    if let entryOff = parser.entryPoint() {
                        InfoRow(label: "Entry Point", value: String(format: "0x%llX", entryOff))
                    }

                    let cdHashes = parser.getCDHashes()
                    if !cdHashes.isEmpty {
                        InfoRow(label: "CDHash", value: cdHashes.joined(separator: "\n"))
                    }
                }

                let x509Certs = parser.x509Certificates()
                if !x509Certs.isEmpty {
                    Section(header: Text(String(format: NSLocalizedString("Signatures & Certificates (%d)", comment: ""), x509Certs.count))) {
                        ForEach(Array(x509Certs.enumerated()), id: \.offset) { index, cert in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cert.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(String(format: NSLocalizedString("Serial: %@", comment: ""), cert.serialNumber))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if cert.expiryDate != Date.distantPast {
                                    Text(String(format: NSLocalizedString("Expires: %@", comment: ""), formatDate(cert.expiryDate)))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let ent = try? parser.entitlements(), !ent.isEmpty {
                    Section(header: Text("Entitlements")) {
                        NavigationLink(destination: ResourceTextViewer(title: NSLocalizedString("Entitlements", comment: ""), explicitContent: ent)) {
                            HStack {
                                Image(systemName: "lock.doc.fill")
                                    .foregroundColor(.green)
                                Text("Embedded Entitlements")
                                    .font(.subheadline)
                                Spacer()
                                Text("XML")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                let libs = parser.linkedLibraries()
                if !libs.isEmpty {
                    Section(header: Text(String(format: NSLocalizedString("Linked Libraries (%d)", comment: ""), libs.count))) {
                        ForEach(libs, id: \.self) { lib in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                                Text(lib)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                let segs = parser.segments()
                if !segs.isEmpty {
                    Section(header: Text(String(format: NSLocalizedString("Segments (%d)", comment: ""), segs.count))) {
                        ForEach(segs, id: \.name) { seg in
                            HStack {
                                Text(seg.name)
                                    .font(.system(size: 13, design: .monospaced))
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: NSLocalizedString("offset: %@  size: %@", comment: ""), String(format: "0x%llX", seg.offset), ByteCountFormatter.string(fromByteCount: Int64(seg.size), countStyle: .file)))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("Raw Dump")) {
                    NavigationLink(destination: ResourceTextViewer(title: NSLocalizedString("Mach-O Dump", comment: ""), explicitContent: dumpText)) {
                        HStack {
                            Image(systemName: "doc.plaintext.fill")
                                .foregroundColor(.blue)
                            Text("View Full Mach-O Dump")
                                .font(.subheadline)
                        }
                    }
                }
            } else if isLoaded {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                    Text("Invalid Mach-O Binary")
                        .font(.headline)
                    Text(String(format: NSLocalizedString("Could not parse %@ as a valid Mach-O binary.", comment: ""), url.lastPathComponent))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Parsing Mach-O\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !dumpText.isEmpty {
                    SwiftUI.Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: [dumpText])
        }
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle(url.lastPathComponent)
        .onAppear {
            guard !isLoaded else { return }
            isLoaded = true
            loadMachO()
        }
    }

    private func loadMachO() {
        guard let p = try? MachOParser(url: url) else { return }
        self.parser = p
        self.dumpText = generateDumpText(p)
    }

    private func generateDumpText(_ p: MachOParser) -> String {
        var info = "--- Mach-O Binary Info: \(url.lastPathComponent) ---\n"
        info += "Path: \(url.path)\n"
        info += "Size: \(formatSize(url))\n"
        info += "Architectures: \(p.architectures().joined(separator: ", "))\n"
        if let platform = p.platformType() {
            info += "Platform: \(platform)\n"
        }
        if let minOS = p.minimumOSVersion() {
            info += "Min OS Version: \(minOS)\n"
        }
        info += "Encrypted (DRM): \(p.isEncrypted() ? "Yes" : "No")\n"
        if let bundleID = p.bundleIdentifier() {
            info += "Bundle ID: \(bundleID)\n"
        }
        if let teamID = p.teamID() {
            info += "Team ID: \(teamID)\n"
        }
        if let entry = p.entryPoint() {
            info += "Entry Point: \(String(format: "0x%llX", entry))\n"
        }
        let cdHashes = p.getCDHashes()
        if !cdHashes.isEmpty {
            info += "CDHashes:\n"
            for hash in cdHashes {
                info += "  \(hash)\n"
            }
        }

        let certs = p.certificates()
        if !certs.isEmpty {
            info += "Certificates (\(certs.count)):\n"
            for (index, cert) in certs.enumerated() {
                let subject = X509Certificate(der: cert)?.name ?? "Certificate \(index + 1) (\(cert.count) bytes)"
                info += "  [\(index)] \(subject)\n"
            }
        }

        let libs = p.linkedLibraries()
        if !libs.isEmpty {
            info += "Linked Libraries (\(libs.count)):\n"
            for lib in libs {
                info += "  - \(lib)\n"
            }
        }

        let segs = p.segments()
        if !segs.isEmpty {
            info += "Segments (\(segs.count)):\n"
            for seg in segs {
                info += "  - \(seg.name) (offset: \(String(format: "0x%llX", seg.offset)), size: \(ByteCountFormatter.string(fromByteCount: Int64(seg.size), countStyle: .file)))\n"
            }
        }

        if let ent = try? p.entitlements(), !ent.isEmpty {
            info += "\n--- Embedded Entitlements ---\n"
            info += ent
            info += "\n"
        }

        info += "----------------------------------------"
        return info
    }

    private func formatSize(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
