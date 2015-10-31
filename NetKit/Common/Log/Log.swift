//
//  Log.swift
//  NetKit
//
//  Created by Mike Godenzi on 01.10.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public func Log(@autoclosure message :  () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	print("\(file) - \(function) [\(line)] \(message())")
#endif
}

public func LogI(@autoclosure message :  () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	Log("\n\n[INFO]\n\n \(message()) \n\n", line: line, function: function, file: file)
#endif
}

public func LogW(@autoclosure message :  () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	Log("\n\n[WARNING]\n\n \(message())", line: line, function: function, file: file)
#endif
}

public func LogE(@autoclosure message :  () -> String, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	Log("\n\n[ERROR]\n\n \(message()) \n\n", line: line, function: function, file: file)
#endif
}

public func Log(@autoclosure error :  () -> NSError?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	if let error = error() {
		LogE(error.localizedDescription, line: line, function: function, file: file)
	}
#endif
}

public func Dump(@autoclosure request req :  () -> NSURLRequest?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	var message = ""
	if let request = req() {
		let method = request.HTTPMethod ?? "GET"
		let URL = request.URL?.absoluteString ?? ""
		let headers = request.allHTTPHeaderFields?.reduce("") { (value, element) -> String in
			return value + "\n\(element.0): \(element.1)"
		} ?? ""
		message += "*** REQUEST ***"
		message += "\nHTTP Method: \(method)"
		message += "\nURL: \(URL)"
		message += "\nHeaders: \(headers)"
	}
	LogI(message, line: line, function: function, file: file)
#endif
}

public func Dump(@autoclosure response res :  () -> NSHTTPURLResponse?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	var message = ""
	if let response = res() {
		let URL = response.URL?.absoluteString ?? ""
		let headers = response.allHeaderFields.reduce("") { (value, element) -> String in
			return value + "\n\(element.0): \(element.1)"
		}
		message += "*** RESPONSE ***"
		message += "\nHTTP Status Code \(response.statusCode) \(NSHTTPURLResponse.localizedStringForStatusCode(response.statusCode))"
		message += "\nURL: \(URL)"
		message += "\nHeaders: \(headers)"
	}
	LogI(message, line: line, function: function, file: file)
#endif
}

public func Dump(@autoclosure data dat :  () -> NSData?, line : Int = __LINE__, function : StaticString = __FUNCTION__, file : StaticString = __FILE__) {
#if DEBUG
	var message : String?
	if let data = dat() {
		if data.length > 0 {
			message = (NSString(data: data, encoding: NSASCIIStringEncoding)! as String)
		}
	}
	if let m = message {
		LogI(m, line: line, function: function, file: file)
	}
#endif
}
