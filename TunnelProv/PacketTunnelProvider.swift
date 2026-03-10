//
//  PacketTunnelProvider.swift
//  TunnelProv
//
//  Packet tunnel that routes traffic between the device IP and the fake tunnel IP,
//  enabling SideStore to communicate with itself for app refresh/install.
//
//  Original implementation by Stossy11 (LocalDevVPN project).
//

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    var tunnelDeviceIp: String  = "10.7.0.0"
    var tunnelFakeIp: String    = "10.7.0.1"
    var tunnelSubnetMask: String = "255.255.255.0"

    private var deviceIpValue: UInt32 = 0
    private var fakeIpValue: UInt32   = 0

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        if let ip   = options?["TunnelDeviceIP"]   as? String { tunnelDeviceIp   = ip   }
        if let ip   = options?["TunnelFakeIP"]     as? String { tunnelFakeIp     = ip   }
        if let mask = options?["TunnelSubnetMask"] as? String { tunnelSubnetMask = mask }

        deviceIpValue = ipToUInt32(tunnelDeviceIp)
        fakeIpValue   = ipToUInt32(tunnelFakeIp)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelDeviceIp)
        let ipv4 = NEIPv4Settings(addresses: [tunnelDeviceIp], subnetMasks: [tunnelSubnetMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: tunnelDeviceIp, subnetMask: tunnelSubnetMask)]
        ipv4.excludedRoutes = [.default()]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { error in
            guard error == nil else { return completionHandler(error) }
            self.setPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func setPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            let fakeip   = self.fakeIpValue
            let deviceip = self.deviceIpValue
            var modified = packets
            for i in modified.indices where protocols[i].int32Value == AF_INET && modified[i].count >= 20 {
                modified[i].withUnsafeMutableBytes { bytes in
                    guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                    let src = UInt32(bigEndian: ptr[3])
                    let dst = UInt32(bigEndian: ptr[4])
                    if src == deviceip { ptr[3] = fakeip.bigEndian   }
                    if dst == fakeip   { ptr[4] = deviceip.bigEndian }
                }
            }
            self.packetFlow.writePackets(modified, withProtocols: protocols)
            self.setPackets()
        }
    }

    private func ipToUInt32(_ ip: String) -> UInt32 {
        let parts = ip.split(separator: ".")
        guard parts.count == 4,
              let b1 = UInt32(parts[0]), let b2 = UInt32(parts[1]),
              let b3 = UInt32(parts[2]), let b4 = UInt32(parts[3]) else { return 0 }
        return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
    }
}
