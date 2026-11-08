import Foundation
import CryptoKit

final class Feed: NSObject, XMLParserDelegate {
    var attributes: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "enclosure" { attributes.append(attributeDict) }
    }
}
func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}
guard CommandLine.arguments.count == 4 else { fail("Usage: verify-appcast.swift feed.xml archive.zip Info.plist") }
let arguments = CommandLine.arguments
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: arguments[3])), format: nil) as! [String: Any]
guard let encodedKey = info["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: encodedKey) else { fail("Missing app verification key.") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
let feed = Feed()
let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: arguments[1])))
parser.delegate = feed
guard parser.parse(), feed.attributes.count == 1, let item = feed.attributes.first,
      let url = item["url"].flatMap(URL.init(string:)), url.scheme == "https", url.host == "github.com",
      url.lastPathComponent == URL(fileURLWithPath: arguments[2]).lastPathComponent,
      item["length"] == String(data.count),
      let signature = item["sparkle:edSignature"].flatMap({ Data(base64Encoded: $0) }),
      key.isValidSignature(signature, for: data)
else { fail("The update feed does not match the archive or the app's verification key.") }
print("Verified the update archive against the public key embedded in Morrow.")
