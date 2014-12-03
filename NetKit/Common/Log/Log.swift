//
//  Log.swift
//  NetKit
//
//  Created by Mike Godenzi on 01.10.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public func Log(message : @autoclosure () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	println("\(file) - \(function) [\(line)] \(message())")
#endif
}

public func LogI(message : @autoclosure () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	Log("\n\n[INFO]\n\n \(message()) \n\n", line: line, function: function, file: file)
#endif
}

public func LogW(message : @autoclosure () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	Log("\n\n[WARNING]\n\n \(message())", line: line, function: function, file: file)
#endif
}

public func LogE(message : @autoclosure () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	Log("\n\n[ERROR]\n\n \(message()) \n\n", line: line, function: function, file: file)
#endif
}

public func Log(error : @autoclosure () -> NSError?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	if let _error = error() {
		LogE(_error.localizedDescription, line: line, function: function, file: file)
	}
#endif
}

public func Dump(request req : @autoclosure () -> NSURLRequest?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	var message = ""
	if let request = req() {
		var method = request.HTTPMethod ?? "GET"
		var URL = request.URL.absoluteString ?? ""
		var headers = request.allHTTPHeaderFields?.description ?? ""
		message += "*** REQUEST ***"
		message += "\nHTTP Method: \(method)"
		message += "\nURL: \(URL)"
		message += "\nHeaders: \(headers)"
	}
	LogI(message, line: line, function: function, file: file)
#endif
}

public func Dump(response res : @autoclosure () -> NSHTTPURLResponse?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	var message = ""
	if let response = res() {
		var URL = response.URL?.absoluteString ?? ""
		var headers = response.allHeaderFields.description ?? ""
		message += "*** RESPONSE ***"
		message += "\nHTTP Status Code \(response.statusCode) \(NSHTTPURLResponse.localizedStringForStatusCode(response.statusCode))"
		message += "\nURL: \(URL)"
		message += "\nHeaders: \(headers)"
	}
	LogI(message, line: line, function: function, file: file)
#endif
}

public func Dump(data dat : @autoclosure () -> NSData?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	var message : String?
	if let data = dat() {
		if data.length > 0 {
			message = NSString(data: data, encoding: NSASCIIStringEncoding)!
		}
	}
	if let m = message {
		LogI(m, line: line, function: function, file: file)
	}
#endif
}
