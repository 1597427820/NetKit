//
//  HTTPResponseParser.swift
//  NetKit
//
//  Created by Mike Godenzi on 27.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public protocol DataParser {

	typealias ResultType

	func parseData(data : NSData) throws -> ResultType
	init()
}

public class RawDataParser : DataParser {

	public typealias ResultType = NSData

	public required init() {}

	public func parseData(data : NSData) throws -> ResultType {
		return data
	}
}

public protocol ResponseParser {

	typealias Parser : DataParser

	func parseData(data : NSData, response : NSURLResponse, completion : (result : Parser.ResultType?, error : NSError?) -> ())
	func shouldParseDataForResponse(response : NSURLResponse) throws
}

public enum HTTPResponseParserError : ErrorType {
	case Unknown
	case CannotParse(String)
}

public class HTTPResponseParser<P : DataParser> : ResponseParser {

	public typealias Parser = P

	public var acceptedMIMETypes = [String]()

	public init() {}

	final public func parseData(data : NSData, response : NSURLResponse, completion : (result : Parser.ResultType?, error : NSError?) -> ()) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
			do {
				let result : Parser.ResultType? = try Parser().parseData(data)
				dispatch_async(dispatch_get_main_queue()) { () -> Void in
					completion(result: result, error: nil)
				}
			} catch {
				dispatch_async(dispatch_get_main_queue()) { () -> Void in
					completion(result: nil, error: error as NSError)
				}
			}
		}
	}

	public func shouldParseDataForResponse(response : NSURLResponse) throws {
		let MIMEType = response.MIMEType ?? ""
		let result = acceptedMIMETypes.contains(MIMEType) || response.URL?.pathExtension?.lowercaseString == "json"
		if (!result) {
			let message = "Unexpected Content-Type, received \(MIMEType), expected \(acceptedMIMETypes)"
			throw HTTPResponseParserError.CannotParse(message)
		}
	}
}

public class DataResponseParser : HTTPResponseParser<RawDataParser> {

	public override func shouldParseDataForResponse(response : NSURLResponse) throws {}
}
