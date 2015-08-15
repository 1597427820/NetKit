//
//  HTTPRequestBuilder.swift
//  NetKit
//
//  Created by Mike Godenzi on 27.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public protocol RequestBuilder {
	func buildRequest(request : NSURLRequest, parameters : NSDictionary?) throws -> NSURLRequest
}

public class HTTPRequestBuilder : RequestBuilder {
	public var percentEncodeParameters = true
	public var stringEncoding = NSUTF8StringEncoding

	private let methodsWithParameterizedURL = ["GET", "HEAD", "DELETE"]

	public required init() {}

	public func buildRequest(request: NSURLRequest, parameters: NSDictionary?) throws -> NSURLRequest {

		guard let parameters = parameters as? [String:String] else { return request }

		let parameterString = formURLEncodedParameters(parameters, encode: false)
		let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
		let method = request.HTTPMethod?.uppercaseString ?? "GET"
		if methodsWithParameterizedURL.contains(method) {
			let URL = request.URL
			let URLComponents = NSURLComponents(string: URL?.absoluteString ?? "")
			if percentEncodeParameters {
				URLComponents?.query = parameterString
			} else {
				URLComponents?.percentEncodedQuery = parameterString
			}
			mutableRequest.URL = URLComponents?.URL
		} else {
			let data = parameterString.dataUsingEncoding(stringEncoding, allowLossyConversion: false)
			mutableRequest.HTTPBody = data
			let charset : NSString = CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(stringEncoding))
			let contentType = "application/x-www-form-urlencoded; charset=\(charset)"
			mutableRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
		}

		return mutableRequest.copy() as! NSURLRequest
	}
}

public class JSONRequestBuilder : HTTPRequestBuilder {

	public override func buildRequest(request: NSURLRequest, parameters: NSDictionary?) throws -> NSURLRequest {
		let error: NSError! = NSError(domain: "Migrator", code: 0, userInfo: nil)
		guard let parameters = parameters else { throw error }

		let method = request.HTTPMethod?.uppercaseString ?? "GET"
		var result : NSURLRequest

		if !methodsWithParameterizedURL.contains(method) {
			let data = try NSJSONSerialization.dataWithJSONObject(parameters, options: NSJSONWritingOptions.PrettyPrinted)
			let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
			mutableRequest.HTTPBody = data
			let charset : NSString = CFStringConvertEncodingToIANACharSetName(CFStringBuiltInEncodings.UTF8.rawValue)
			let contentType = "application/json; charset=\(charset)"
			mutableRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
			result = mutableRequest.copy() as! NSURLRequest
		} else {
			result = try super.buildRequest(request, parameters: parameters)
		}

		return result
	}
}

private func formURLEncodedParameters(parameters : [String:String], encode : Bool) -> String {
	var result = ""
	let keys = parameters.keys.sort { $0 < $1 }
	let count = keys.count
	if keys.count > 0 {
		for i in 0..<count {
			let key = encode ? keys[i].URLEncodedString() : keys[i]
			let value = encode ? parameters[key]!.URLEncodedString() : parameters[key]!
			result += "\(key)=\(value)"
			if i != count {
				result += "&"
			}
		}
	}
	return result
}

extension String {
	func URLEncodedString() -> String {
		return CFURLCreateStringByAddingPercentEscapes(nil, self as NSString, nil, "!*'();:@&=+$,/?%#[]", CFStringBuiltInEncodings.UTF8.rawValue) as NSString as String;
	}
}
