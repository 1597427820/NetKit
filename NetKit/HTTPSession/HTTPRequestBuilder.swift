//
//  HTTPRequestBuilder.swift
//  NetKit
//
//  Created by Mike Godenzi on 27.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public protocol RequestBuilder {
	func buildRequest(request : NSURLRequest, parameters : NSDictionary?, error : NSErrorPointer) -> NSURLRequest?
	init()
}

public class HTTPRequestBuilder : RequestBuilder {
	public var percentEncodeParameters = true
	public var stringEncoding = NSUTF8StringEncoding

	private let methodsWithParameterizedURL = ["GET", "HEAD", "DELETE"]

	public required init() {}

	public func buildRequest(request: NSURLRequest, parameters: NSDictionary?, error : NSErrorPointer) -> NSURLRequest? {
		var result : NSURLRequest? = request
		if let _parameters = parameters as? [String:String] {
			let parameterString = FormURLEncodedParameters(_parameters, false)
			let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
			let method = request.HTTPMethod?.uppercaseString ?? "GET"
			if contains(methodsWithParameterizedURL, method) {
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
			result = mutableRequest
		}
		return result;
	}
}

public class JSONRequestBuilder : HTTPRequestBuilder {

	public override func buildRequest(request: NSURLRequest, parameters: NSDictionary?, error : NSErrorPointer) -> NSURLRequest? {
		var result : NSURLRequest? = request
		if let _parameters = parameters {
			let method = request.HTTPMethod?.uppercaseString ?? "GET"
			if !contains(methodsWithParameterizedURL, method) {
				let data = NSJSONSerialization.dataWithJSONObject(_parameters, options: NSJSONWritingOptions.PrettyPrinted, error: error)
				if let _data = data {
					var mutableRequest = request.mutableCopy() as! NSMutableURLRequest
					mutableRequest.HTTPBody = data
					let charset : NSString = CFStringConvertEncodingToIANACharSetName(CFStringBuiltInEncodings.UTF8.rawValue)
					let contentType = "application/json; charset=\(charset)"
					mutableRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
					result = mutableRequest
				} else {
					result = nil
				}
			} else {
				result = super.buildRequest(request, parameters: parameters, error: error)
			}
		}
		return result
	}
}

private func FormURLEncodedParameters(parameters : [String:String], encode : Bool) -> String {
	var result = ""
	let keys = sorted(parameters.keys) { $0 < $1 }
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
		return CFURLCreateStringByAddingPercentEscapes(nil, self as NSString, nil, "!*'();:@&=+$,/?%#[]", CFStringBuiltInEncodings.UTF8.rawValue) as NSString as! String;
	}
}
