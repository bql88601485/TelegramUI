import Foundation
import Postbox
import TelegramCore

func legacyImageLocationUri(resource: MediaResource) -> String? {
    if let resource = resource as? CloudFileMediaResource {
        return "\(resource.datacenterId)_\(resource.volumeId)_\(resource.localId)_\(resource.secret)"
    }
    return nil
}

private let legacyImageUriExpr = try? NSRegularExpression(pattern: "([-\\d]+)_([-\\d]+)_([-\\d]+)_([-\\d]+)", options: [])

func resourceFromLegacyImageUri(_ uri: String) -> MediaResource? {
    guard let legacyImageUriExpr = legacyImageUriExpr else {
        return nil
    }
    let matches = legacyImageUriExpr.matches(in: uri, options: [], range: NSRange(location: 0, length: uri.characters.count))
    if let match = matches.first {
        let nsString = uri as NSString
        let datacenterId = nsString.substring(with: match.rangeAt(1))
        let volumeId = nsString.substring(with: match.rangeAt(2))
        let localId = nsString.substring(with: match.rangeAt(3))
        let secret = nsString.substring(with: match.rangeAt(4))
        
        guard let nDatacenterId = Int(datacenterId) else {
            return nil
        }
        guard let nVolumeId = Int64(volumeId) else {
            return nil
        }
        guard let nLocalId = Int32(localId) else {
            return nil
        }
        guard let nSecret = Int64(secret) else {
            return nil
        }
        
        return CloudFileMediaResource(datacenterId: nDatacenterId, volumeId: nVolumeId, localId: nLocalId, secret: nSecret, size: nil)
    }
    return nil
}