// Shared by certificate verification and its diagnostics.

public enum CertificateStatus: Equatable, Sendable {
    case valid(isCrossSigned: Bool)
    case revoked
    case expired
}
