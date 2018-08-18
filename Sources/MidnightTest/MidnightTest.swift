import XCTest
import Kitura
import KituraNet
import Foundation

// MARK: MidnightTestCase

open class MidnightTestCase: XCTestCase {
    /// Router object used when Kitura is started.
    public var router: Router? = nil
    /// Initial ClientRequest Options.
    public var requestOptions: [ClientRequest.Options] = []
    /// Boundary used when generating mutlipart data.
    ///
    /// - SeeAlso: multipartEncode()
    lazy public var multipartBoundary = "----" + UUID().uuidString
    /// Structure of a ResponseChecker function.
    public typealias ResponseChecker = (Data, ClientResponse) -> Void

    /// Type of form encoding to use when doing a POST response.
    ///
    /// - SeeAlso: testPostResponse()
    public enum FormEncodingType {
        case Multipart, UrlEncoded
    }

    /// Errors for MidnightTest
    public enum MidnightTestError: Swift.Error {
        /// Something unexpected happened when trying to do URL encoding.
        ///
        /// - SeeAlso: urlEncode()
        case UrlEncodingFailed
    }

    override open func setUp() {
        guard let router = router else {
            fatalError("Please set the router property.")
        }
        // Determine the port to use for Kitura from the passed options
        var port: Int16?
        optionLoop: for option in requestOptions {
            switch option {
            case .port(let optionPort):
                // If a port was given directly, just use that.
                port = optionPort
            case .schema(let schema):
                // Else use the default port for the given schema.
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
        // Start Kitura
        Kitura.addHTTPServer(onPort: Int(port ?? 80), with: router)
        Kitura.start()
    }

    override open func tearDown() {
        Kitura.stop()
    }

    /// Main test function.
    ///
    /// - Parameters:
    ///     - options: ClientRequest Options to build the ClientRequest
    ///     - body: The HTTP request body, if any.
    ///     - checker: Array of ResponseChecker functions to check the response with.
    public func testResponse(options: [ClientRequest.Options], body: Data? = nil, checker: [ResponseChecker]) {
        // Initiate request
        let req = HTTP.request(options) { response in
            guard let response = response else {
                XCTFail("Could not fetch response.")
                return
            }
            // Read and store the response body. We have to pass it separately
            // to the checkers because the methods to read the body empty the
            // buffer (so they can't be called twice).
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
    ///
    /// Wrapper for the main testResponse() function.
    ///
    /// - Parameters:
    ///     - path: The path to make a request to.
    ///     - method: The HTTP method to use, lower-cased.
    ///     - headers: A [String: String] dictionary of HTTP request headers
    ///     - body: HTTP request body, if any.
    ///     - checker: ResponseChecker functions to check the repsose with.
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

    /// Even simpler test function for passing a body as a string.
    ///
    /// Wrapper for the main testResponse() function.
    ///
    /// - Parameters:
    ///     - path: The path to make a request to.
    ///     - method: The HTTP method to use, lower-cased.
    ///     - headers: A [String: String] dictionary of HTTP request headers
    ///     - body: HTTP request body, if any, as a string.
    ///     - checker: ResponseChecker functions to check the repsose with.
    public func testResponse(
        _ path: String,
        method: String = "get",
        headers: [String: String] = [:],
        body: String,
        checker: ResponseChecker...
        ) {
        // Convert the body string to a Data.
        let bodyData = body.data(using: .utf8)
        let options = appendToDefaultOptions(path: path, method: method, headers: headers)
        testResponse(options: options, body: bodyData, checker: checker)
    }

    /// Simplified test function for POST rquests.
    ///
    /// Wrapper for the main testResponse() function.
    ///
    /// - Parameters:
    ///     - path: The path to make a request to.
    ///     - fields: A [String: [String]] of field data to be posted.
    ///     - enctype: The FormEncodingType used for the data when posting.
    ///     - headers: A [String: String] dictionary of HTTP request headers
    ///     - checker: ResponseChecker functions to check the repsose with.
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

    /// Add path, method, and header data to a ClientRequest.Options array.
    ///
    /// - Parameters:
    ///     - path: The path.
    ///     - method: The HTTP request method.
    ///     - headers: A [String: String] dictionary of HTTP request headers.
    ///
    ///     - Returns: An array of ClientRequest.Options.
    private func appendToDefaultOptions(path: String, method: String, headers: [String: String]?) -> [ClientRequest.Options] {
        var options = requestOptions
        options.append(.path(path))
        options.append(.method(method))
        if let headers = headers {
            options.append(.headers(headers))
        }
        return options
    }

    /// Generate a ResponseChecker implementation to check if the response body
    /// contain a string.
    ///
    /// - Parameters
    ///     - string: The string to find in the response.
    ///
    /// - Returns: A ResponseChecker implementation.
    public func checkString(_ string: String) -> ResponseChecker {
        return { body, response in
            guard let bodyString = String(data: body, encoding: .utf8) else {
                XCTFail("Could not read response body as string.")
                return
            }
            XCTAssert(bodyString.contains(string), "Could not find \"\(string)\" in response body.")
        }
    }

    /// Generate a ResponseChecker implementation to check if the response has
    /// a certain status code.
    ///
    /// - Parameters
    ///     - code: The HTTPStatusCode to check for in the response..
    ///
    /// - Returns: A ResponseChecker implementation.
    public func checkStatus(_ code: HTTPStatusCode) -> ResponseChecker {
        return { body, response in
            XCTAssertEqual(response.httpStatusCode, code, "Unexpected response status code (expecting \(code.rawValue), found \(response.httpStatusCode.rawValue)).")
        }
    }

    /// URL encode post data.
    ///
    /// - Throws: MidnightTestError
    /// - Parameters:
    ///     - fields: A [String: [String]?] dictionary of data to post.
    ///
    /// - Returns: The URL-encoded post data as a string.
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

    /// Multi-part encode post data.
    ///
    /// - Parameters:
    ///     - fields: A [String: [String]?] dictionary of data to post.
    ///
    /// - Returns: The encoded post data as a string.
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
