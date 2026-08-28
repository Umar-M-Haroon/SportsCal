import Foundation
import X509

// Apple App Attestation Root CA — the single trust anchor for every attestation
// certificate chain we accept.
//
// Source: https://www.apple.com/certificateauthority/private/
// Direct:  https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
// SHA256 fingerprint:
//   1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32
//
// Pinned as source rather than loaded from disk on purpose: it is the root of
// trust for the whole attestation scheme, and embedding it means a
// misconfigured deploy can't silently drop the trust anchor and leave us
// validating against the system store. Valid until 2045-03-15.
//
// If Apple ever rotates this root, add the new PEM alongside the old one — the
// store accepts multiple anchors, so a rotation is non-breaking.
extension AppAttestVerifier {

    static let appleRootCAPEM: String = """
-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----
"""

    /// Parsed once at first use; a parse failure here is a programmer error
    /// (the PEM above is a compile-time constant), so it traps rather than
    /// degrading into an empty store that would trust nothing — or worse,
    /// anything.
    static let appleRootStore: CertificateStore = {
        guard let root = try? Certificate(pemEncoded: appleRootCAPEM) else {
            fatalError("Apple App Attestation Root CA failed to parse — the embedded PEM is corrupt")
        }
        return CertificateStore([root])
    }()
}
