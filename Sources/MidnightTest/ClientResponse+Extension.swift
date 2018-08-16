import Foundation
import Kitura

extension ClientResponse {
    lazy public var bodyAsString: String? = { try? readString() }
}
