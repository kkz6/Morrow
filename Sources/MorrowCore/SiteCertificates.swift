import Foundation
import Security

public struct LocalHTTPSCertificate: Sendable {
    public let domain: String
    public let validUntil: Date?

    public var summary: String {
        guard let validUntil else { return "\(domain) · Certificate not issued" }
        let label = validUntil > Date() ? "Valid until" : "Expired"
        return "\(domain) · \(label) \(validUntil.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension SiteManager {
    static let siteCertificateDays = 368

    var intermediateCertificateURL: URL {
        certificateURL.deletingLastPathComponent().appendingPathComponent("intermediate.crt")
    }

    func siteCertificateDirectory(_ site: LocalSite) -> URL {
        base.appendingPathComponent("caddy-data/certificates/local").appendingPathComponent(site.domain)
    }

    func secureSites(_ web: WebWorkspace) -> [LocalSite] {
        web.sites.filter { $0.https && !$0.isIgnoredForHosting && $0.issue == nil }
    }

    static func certificateExpiration(_ file: URL) -> Date? {
        guard let pem = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return certificateExpiration(pem: pem)
    }

    static func certificateExpiration(pem: String) -> Date? {
        // Caddy serves the leaf and its issuing intermediate from the same PEM.
        // The earliest expiration in that chain is the one the client sees.
        let oid = kSecOIDX509V1ValidityNotAfter as String
        let certificates = pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst()
        return certificates.compactMap { block -> Date? in
            guard let body = block.components(separatedBy: "-----END CERTIFICATE-----").first,
                  let der = Data(base64Encoded: body, options: .ignoreUnknownCharacters),
                  let certificate = SecCertificateCreateWithData(nil, der as CFData),
                  let properties = SecCertificateCopyValues(certificate, [oid] as CFArray, nil) as? [String: [String: Any]],
                  let time = properties[oid]?[kSecPropertyKeyValue as String] as? NSNumber else { return nil }
            return Date(timeIntervalSinceReferenceDate: time.doubleValue)
        }.min()
    }

    func httpsCertificates(_ web: WebWorkspace) -> [LocalHTTPSCertificate] {
        let rootExpiration = Self.certificateExpiration(certificateURL)
        return secureSites(web).compactMap { site in
            guard (try? Self.validateDomain(site.domain, web: web)) == site.domain else { return nil }
            let file = siteCertificateDirectory(site).appendingPathComponent(site.domain + ".crt")
            let expiration = Self.certificateExpiration(file).map { min($0, rootExpiration ?? $0) }
            return LocalHTTPSCertificate(domain: site.domain, validUntil: expiration)
        }.sorted { $0.domain < $1.domain }
    }

    public func httpsCertificates() throws -> [LocalHTTPSCertificate] {
        httpsCertificates(try store.load().web)
    }
}
