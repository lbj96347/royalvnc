import Foundation

/// Coarse protocol progress only; never contains credentials or key material.
public enum VNCHandshakePhase: String, Sendable {
    case connecting, protocolVersion, securityTypes, accountChallenge, credentials
    case keyAgreement, authenticationResult, serverInit, ready
}
