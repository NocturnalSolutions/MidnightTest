import XCTest
import Kitura
import KituraNet
import Foundation

open class MidnightTestCase: XCTestCase {
    public var router: Router? = nil
    public var requestOptions: [ClientRequest.Options] = []
    lazy public var multipartBoundary = "----" + UUID().uuidString
    public typealias ResponseChecker = (Data, ClientResponse) -> Void

    public enum FormEncodingType {
        case Multipart, UrlEncoded
    }

    public enum MidnightTestError: Swift.Error {
        case UrlEncodingFailed
    }

    override open func setUp() {
        guard let router = router else {
            fatalError("Please set the router property.")
        }
        /// Determine the port to use for Kitura from the passed options
        var port: Int16?
        optionLoop: for option in requestOptions {
            switch option {
            case .port(let optionPort):
                port = optionPort
                break optionLoop
            case .schema(let schema):
                if (port == nil) {
                    let lowerSchema = schema.lowercased()
                    if lowerSchema == "https://" {
                        port = 443
                    }
                    else if lowerSchema == "http://" {
                        port = 80
                    }
                }
            default:
                continue
            }
        }
        Kitura.addHTTPServer(onPort: Int(port ?? 80), with: router)
        Kitura.start()
    }

    override open func tearDown() {
        Kitura.stop()
    }

    /// Main test function
    public func testResponse(options: [ClientRequest.Options], body: Data? = nil, checker: [ResponseChecker]) {
        // Initiate request
        let req = HTTP.request(options) { response in
            guard let response = response else {
                XCTFail("Could not fetch response.")
                return
            }
            // Using 2000 'cuz that's what ClientResponse uses
            var responseBody: Data = Data(capacity: 2000)
            guard let _ = try? response.readAllData(into: &responseBody) else {
                XCTFail("Could not read response data.")
                return
            }
            // Loop through checking functions
            for checkerFunc in checker {
                checkerFunc(responseBody, response)
            }
        }
        // Write body, if any
        if let body = body {
            req.write(from: body)
        }
        // Execute request
        req.end()
    }

    /// Simplified test function.
    public func testResponse(
        _ path: String,
        method: String = "get",
        headers: [String: String] = [:],
        body: Data? = nil,
        checker: ResponseChecker...
        ) {
        let options = appendToDefaultOptions(path: path, method: method, headers: headers)
        testResponse(options: options, body: body, checker: checker)
    }

    // Even simpler test function for passing a body as a string.
    public func testResponse(
        _ path: String,
        method: String = "get",
        headers: [String: String] = [:],
        body: String,
        checker: ResponseChecker...
        ) {
        let bodyData = body.data(using: .utf8)
        let options = appendToDefaultOptions(path: path, method: method, headers: headers)
        testResponse(options: options, body: bodyData, checker: checker)
    }

    public func testPostResponse(
        _ path: String,
        fields: [String: [String]?],
        enctype: FormEncodingType = .UrlEncoded,
        headers: [String: String] = [:],
        checker: ResponseChecker...
        ) throws {
        let body: String
        var headers = headers
        if enctype == .UrlEncoded {
            body = try urlEncode(fields)
        }
        else {
            body = multipartEncode(fields)
            headers["Content-Type"] = "multipart/form-data; boundary=" + multipartBoundary
        }
        let bodyData = body.data(using: .utf8)
        let options = appendToDefaultOptions(path: path, method: "post", headers: headers)
        testResponse(options: options, body: bodyData, checker: checker)
    }

    private func appendToDefaultOptions(path: String, method: String, headers: [String: String]?) -> [ClientRequest.Options] {
        var options = requestOptions
        options.append(.path(path))
        options.append(.method(method))
        if let headers = headers {
            options.append(.headers(headers))
        }
        return options
    }

    public func checkString(_ string: String) -> ResponseChecker {
        return { body, response in
            guard let bodyString = String(data: body, encoding: .utf8) else {
                XCTFail("Could not read response body as string.")
                return
            }
            XCTAssert(bodyString.contains(string), "Could not find \"\(string)\" in response body.")
        }
    }

    public func checkStatus(_ code: HTTPStatusCode) -> ResponseChecker {
        return { body, response in
            XCTAssertEqual(response.httpStatusCode, code, "Unexpected response status code (expecting \(code.rawValue), found \(response.httpStatusCode.rawValue)).")
        }
    }

    private func urlEncode(_ fields: [String: [String]?]) throws -> String {
        var parts: [String] = []
        for (key, values) in fields {
            guard let escKey = key.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlPathAllowed) else {
                throw MidnightTestError.UrlEncodingFailed
            }
            if let values = values {
                for value in values {
                    guard let escValue = value.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlPathAllowed) else {
                        throw MidnightTestError.UrlEncodingFailed
                    }
                    parts.append("\(escKey)=\(escValue)")
                }
            }
            else {
                parts.append(escKey)
            }
        }
        return parts.joined(separator: "&")
    }

    private func multipartEncode(_ fields: [String: [String]?]) -> String {
        var body = "--" + multipartBoundary
        let rn = "\r\n"
        for (key, values) in fields {
            if let values = values {
                for value in values {
                    body += rn + "Content-Disposition: form-data; name=\"\(key)\"" + rn
                    body += "Content-Type: text/plain" + rn + rn
                    body += value + rn
                    body += "--" + self.multipartBoundary
                }
            }
        }
        return body + "--"

    }

}
