import Foundation
import GRDB

struct AssetReference: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let assetRefId: String
    let locationType: LocationType
    let uri: String
    var variants: AssetVariants?
    var checksum: String?

    var id: String { assetRefId }

    init(
        assetRefId: String = UUID().uuidString,
        locationType: LocationType,
        uri: String,
        variants: AssetVariants? = nil,
        checksum: String? = nil
    ) {
        self.assetRefId = assetRefId
        self.locationType = locationType
        self.uri = uri
        self.variants = variants
        self.checksum = checksum
    }

    static let databaseTableName = "asset_references"

    enum CodingKeys: String, CodingKey {
        case assetRefId = "asset_ref_id"
        case locationType = "location_type"
        case uri
        case variants
        case checksum
    }

    enum Columns: String, ColumnExpression {
        case assetRefId = "asset_ref_id"
        case locationType = "location_type"
        case uri
        case variants
        case checksum
    }
}

enum LocationType: String, Codable {
    case local
    case cloud
    case remote
}

struct AssetVariants: Codable {
    var original: String?
    var proxy: String?
    var transcoded: String?

    init(original: String? = nil, proxy: String? = nil, transcoded: String? = nil) {
        self.original = original
        self.proxy = proxy
        self.transcoded = transcoded
    }
}
