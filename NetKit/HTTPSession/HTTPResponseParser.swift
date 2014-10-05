//
//  HTTPResponseParser.swift
//  NetKit
//
//  Created by Mike Godenzi on 27.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public protocol ResponseParser {
	func parseData(data : NSData, response : NSURLResponse, completion : (data : AnyObject?, error : NSError?) -> ())
	func shouldParseDataForResponse(response : NSURLResponse, inout error : NSError?) -> Bool
}

public class HTTPResponseParser : ResponseParser {

	private var acceptedMIMETypes : [String] {
		return []
	}

	public func shouldParseDataForResponse(response: NSURLResponse, inout error: NSError?) -> Bool {
		var MIMEType = response.MIMEType ?? ""
		var result = contains(acceptedMIMETypes, MIMEType) || response.URL?.pathExtension.lowercaseString == "json"
		if (!result && error != nil) {
			var message = "Unexpected Content-Type, received \(MIMEType), expected \(acceptedMIMETypes)"
			error! = NSError(domain: "NetKit", code: -128942, userInfo: [NSLocalizedDescriptionKey: message])
		}
		return result
	}

	public init() {}

	public func parseData(data : NSData, response : NSURLResponse, completion : (data : AnyObject?, error : NSError?) -> ()) {
		completion(data: data, error: nil)
	}
}

public class JSONResponseParser : HTTPResponseParser {
	
	private override var acceptedMIMETypes : [String] {
		return ["application/json", "text/javascript"]
	}

	public override func parseData(data: NSData, response: NSURLResponse, completion: (data: AnyObject?, error: NSError?) -> ()) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
			var error : NSError?
			var parsedData : AnyObject? = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers, error:&error)
			completion(data: parsedData, error: error)
		}
	}
}

public class XMLResponseParser : HTTPResponseParser {

	private override var acceptedMIMETypes : [String] {
		return ["application/xml", "text/xml", "application/rss+xml", "application/rdf+xml", "application/atom+xml"]
	}

	public override func parseData(data: NSData, response: NSURLResponse, completion: (data: AnyObject?, error: NSError?) -> ()) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
			var error : NSError?
			var parsedData = XMLElement.XMLElementWithData(data, error: &error)
			completion(data: parsedData, error: error)
		}
	}
}
