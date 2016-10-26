//  URLRequestPolicy.swift
//
//  ProtoKit
//  Copyright © 2016 Trevor Squires.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation

public final class URLRequestPolicy {
    
    public private(set) static var defaultUserAgent: String = {
        let mainBundle = Bundle.main
        let bundleName = mainBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? mainBundle.object(forInfoDictionaryKey: "CFBundleName")
        let bundleVersion = mainBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? mainBundle.object(forInfoDictionaryKey: "CFBundleVersion")
        
        return "\(bundleName!)/\(bundleVersion!)"
    }()

    public lazy var userAgent: String = { return URLRequestPolicy.defaultUserAgent }()

    public var baseURL: URL?
    public var cachePolicy: NSURLRequest.CachePolicy?
    public var timeoutInterval: TimeInterval?
    public var networkServiceType: NSURLRequest.NetworkServiceType?
    public var allowsCellularAccess: Bool?
    public var shouldHandleCookies: Bool?
    public var shouldUsePipelining: Bool?

    public var additionalHeaders: [String: String]?

    public var authorizationToken: String?

    public init() {}
    
    public convenience init(baseURL: URL?) {
        self.init()
        self.baseURL = baseURL
    }
    
    public convenience init(_ original: URLRequestPolicy) {
        self.init()

        userAgent = original.userAgent
        baseURL = original.baseURL
        cachePolicy = original.cachePolicy
        timeoutInterval = original.timeoutInterval
        networkServiceType = original.networkServiceType
        allowsCellularAccess = original.allowsCellularAccess
        shouldHandleCookies = original.shouldHandleCookies
        shouldUsePipelining = original.shouldUsePipelining
        additionalHeaders = original.additionalHeaders
        authorizationToken = original.authorizationToken
    }

    public func setAuthorizationToken(withUserName userName: String, password: String) {
        let encodedPair = encodeBasicToken(withUserName: userName, password: password)
        authorizationToken = "Basic \(encodedPair)"
    }
    
    public func setAuthorizationToken(withBearerToken bearerToken: String) {
        authorizationToken = "Bearer \(bearerToken)"
    }

    public func request(withURL url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        setPolicyValuesForRequest(&request)
        return request
    }

    public func request(withURLComponents components: URLComponents, method: String) -> URLRequest {
        return request(withURL: components.url(relativeTo: baseURL)!, method: method)
    }
    

    public func setPolicyValuesForRequest( _ request: inout URLRequest) {
        if let cachePolicy = cachePolicy {
            request.cachePolicy = cachePolicy
        }
        
        if let timeoutInterval = timeoutInterval {
            request.timeoutInterval = timeoutInterval;
        }

        if let networkServiceType = networkServiceType {
            request.networkServiceType = networkServiceType;
        }
        
        if let allowsCellularAccess = allowsCellularAccess {
            request.allowsCellularAccess = allowsCellularAccess
        }
        
        if let shouldHandleCookies = shouldHandleCookies {
            request.httpShouldHandleCookies = shouldHandleCookies;
        }
        
        if let shouldUsePipelining = shouldUsePipelining {
            request.httpShouldUsePipelining = shouldUsePipelining;
        }
        
        if let saneUserAgentData = userAgent.data(using: String.Encoding.ascii, allowLossyConversion: true) {
            request.setValue(String(data: saneUserAgentData, encoding: String.Encoding.ascii), forHTTPHeaderField: "User-Agent")
        }
        
        if let authorizationToken = authorizationToken {
            request.setValue(authorizationToken, forHTTPHeaderField: "Authorization")
        }
        
        if let additionalHeaders = additionalHeaders {
            setHeaders(additionalHeaders, forRequest: &request)
        }
    }

    public func setHeaders(_ headers: [String: String], forRequest request: inout URLRequest) {
        for (headerKey, headerValue) in headers {
            request.setValue(headerValue, forHTTPHeaderField: headerKey)
        }
    }

    public func setAuthorization(withBearerToken token: String, forRequest request: inout URLRequest) {
        setAuthorization(withToken: "Bearer \(token)", forRequest: &request)
    }
    
    public func setAuthorization(withUsername userName: String, password: String, forRequest request: inout URLRequest) {
        let encodedPair = encodeBasicToken(withUserName: userName, password: password)
        setAuthorization(withToken: "Basic \(encodedPair)", forRequest: &request)
    }
    
    public func setAuthorization(withToken token: String, forRequest request: inout URLRequest) {
        request.setValue(token, forHTTPHeaderField: "Authorization")
    }
    
    public func removeAuthorizationForRequest(_ request: inout URLRequest) {
        request.setValue(nil, forHTTPHeaderField: "Authorization")
    }
    
    private func encodeBasicToken(withUserName userName: String, password: String) -> String {
        guard let pairData = "\(userName):\(password)".data(using: String.Encoding.utf8) else {
            preconditionFailure("empty username and password data")
        }
        return pairData.base64EncodedString(options: NSData.Base64EncodingOptions())
    }
    
}
