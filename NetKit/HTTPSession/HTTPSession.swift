//
//  HTTPSession.swift
//  NetKit
//
//  Created by Mike Godenzi on 27.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation
import UIKit

private var RequestCount : Int = 0

public protocol HTTPSessionBackgroundDelegate : class {
	func HTTPSessionDidFinishEvents(session : NetKit.HTTPSession)
	func HTTPSession(session : NetKit.HTTPSession, task : NSURLSessionTask, didCompleteWithData data : NSData?, error : NSError?)
}

public protocol HTTPSessionBackgroundDownloadDelegate : class {
	func HTTPSession(session : NetKit.HTTPSession, downloadTask : NSURLSessionDownloadTask, didFinishDownloadingToURL URL: NSURL)
}

public class HTTPSession {

	public typealias AuthenticationChallengeCompletionBlock = (disposition : NSURLSessionAuthChallengeDisposition, credential : NSURLCredential) -> ()

	public var acceptedStatusCodes = Range(200..<300)
	public var acceptedMIMETypes : [String] = []
	public var onSessionAuthenticationChallenge : ((challenge : NSURLAuthenticationChallenge, completion : AuthenticationChallengeCompletionBlock) -> ())?
	public var onTaskAuthenticationChallenge : ((task : NSURLSessionTask, challenge : NSURLAuthenticationChallenge, completion : AuthenticationChallengeCompletionBlock) -> ())?
	public weak var backgroundDelegate : HTTPSessionBackgroundDelegate?
	public weak var backgroundDownloadDelegate : HTTPSessionBackgroundDownloadDelegate?

	private struct TaskInfo {

		var data = NSMutableData()
		var parser : ResponseParser?
		var progress : ((bytesWrittenOrRead : Int64, totalBytesWrittenOrRead : Int64, totalBytesExpectedToWriteOrRead : Int64) -> ())?
		var completion : ((data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ())?
		var downloadCompletion : ((URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ())?

		init() {}

		init(data : NSData) {
			self.data.appendData(data)
		}
	}

	final class SessionDelegate : NSObject {

		weak var httpSession : HTTPSession?

		init(session : HTTPSession) {
			self.httpSession = session
			super.init()
		}
	}

	private var taskInfoMap = [Int:TaskInfo]()

	private var configuration : NSURLSessionConfiguration
	private lazy var session : NSURLSession = NSURLSession(configuration: self.configuration, delegate: SessionDelegate(session: self), delegateQueue: nil)
	private var isBackgroundSession : Bool {
		var identifier : String? = self.configuration.identifier
		return  identifier != nil
	}

	required public init(configuration : NSURLSessionConfiguration?) {
		self.configuration = configuration ?? NSURLSessionConfiguration.defaultSessionConfiguration()
	}

	convenience public init() {
		self.init(configuration: nil)
	}

	deinit {
		session.invalidateAndCancel()
	}
}

extension HTTPSession {

	public func startRequest(request : NSURLRequest, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		Dump(request: request)
		Dump(data: request.HTTPBody)
		showNetworkActivityIndicator()
		let task = session.dataTaskWithRequest(request) { [unowned self] (data, response, error) -> Void in
			self.hideNetworkActivityIndicator();
			self.processResponse(response, data: data, error: error, parser: parser, completion: completion)
		}
		task.resume()
	}

	public func startRequest(request : NSURLRequest, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var error : NSError?
		var builtRequest : NSURLRequest? = request
		if let _builder = builder {
			builtRequest = _builder.buildRequest(request, parameters: parameters, error: &error)
		}

		if let _builtRequest = builtRequest {
			startRequest(_builtRequest, parser: parser, completion: completion)
		} else {
			dispatch_async(dispatch_get_main_queue()) {
				completion(data: nil, response: nil, error: error)
			}
		}
	}

	public func downloadRequest(request : NSURLRequest, parameters : NSDictionary?, builder : RequestBuilder?, progress : ((bytesWrittenOrRead : Int64, totalBytesWrittenOrRead : Int64, totalBytesExpectedToWriteOrRead : Int64) -> ())?, completion : (URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ()) {
		var error : NSError?
		var builtRequest = builder?.buildRequest(request, parameters: parameters, error: &error);

		if let _builtRequest = builtRequest {
			var completionHanlder : ((URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ())? = { [unowned self] (URL, response, error) in
				var location = URL
				var validationError = error
				switch (error, response) {
				case let (.None, .Some(_response)):
					if !self.validateResponse(_response, error: &validationError) {
						location = nil;
					}
					fallthrough
				default:
					completion(URL: location, response: response, error: error)
				}
			}
			var taskInfo : TaskInfo? = nil
			if isBackgroundSession || progress != nil {
				taskInfo = TaskInfo()
				taskInfo!.progress = progress
				taskInfo!.downloadCompletion = completionHanlder
				completionHanlder = nil
			}
			Dump(request: builtRequest)
			let task = session.downloadTaskWithRequest(_builtRequest, completionHandler: completionHanlder)
			if let _taskInfo = taskInfo {
				session.delegateQueue.addOperationWithBlock { [unowned self] in
					self.taskInfoMap[task.taskIdentifier] = _taskInfo
				}
			}
			task.resume()
		} else {
			completion(URL: nil, response: nil, error: error)
		}
	}

	public func resumeDownloadWithData(data : NSData, progress : ((bytesWrittenOrRead : Int64, totalBytesWrittenOrRead : Int64, totalBytesExpectedToWriteOrRead : Int64) -> ())?, completion : (URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ()) {
		var completionHanlder : ((URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ())? = { [unowned self] (URL, response, error) in
			var location = URL
			var validationError = error
			switch (error, response) {
			case let (.None, .Some(_response)):
				if !self.validateResponse(_response, error: &validationError) {
					location = nil;
				}
				fallthrough
			default:
				completion(URL: location, response: response, error: error)
			}
		}
		var taskInfo : TaskInfo? = nil
		if isBackgroundSession || progress != nil {
			taskInfo = TaskInfo()
			taskInfo!.progress = progress
			taskInfo!.downloadCompletion = completionHanlder
			completionHanlder = nil
		}
		let task = session.downloadTaskWithResumeData(data, completionHandler: completionHanlder)
		if let _taskInfo = taskInfo {
			session.delegateQueue.addOperationWithBlock { [unowned self] in
				self.taskInfoMap[task.taskIdentifier] = _taskInfo
			}
		}
		task.resume()
	}

	public func resetWithCompletion(completion : () -> ()) {
		session.resetWithCompletionHandler(completion)
	}
}

extension HTTPSession {

	public func GET(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			GET(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		} else {
			var error = NSError(domain: "NetKit", code: -7829, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
			completion(data: nil, response: nil, error: error)
		}
	}

	public func GET(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "GET"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func GETJSON(#URLString : String, parameters : NSDictionary?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		GET(URLString: URLString, parameters: parameters, builder: JSONRequestBuilder(), parser: JSONResponseParser(), completion: completion)
	}

	public func GETJSON(URL : NSURL, parameters : NSDictionary?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		GET(URL, parameters: parameters, builder: JSONRequestBuilder(), parser: JSONResponseParser(), completion: completion)
	}

	public func GETXML(#URLString : String, parameters : NSDictionary?, completion : (xml : XMLElement?, response : NSURLResponse?, error : NSError?) -> ()) {
		GET(URLString: URLString, parameters: parameters, builder: HTTPRequestBuilder(), parser: XMLResponseParser()) { (data, response, error) -> () in
			let xml = data as? XMLElement
			completion(xml: xml, response: response, error: error)
		}
	}

	public func GETXML(URL : NSURL, parameters : NSDictionary?, completion : (xml : XMLElement?, response : NSURLResponse?, error : NSError?) -> ()) {
		GET(URL, parameters: parameters, builder: HTTPRequestBuilder(), parser: XMLResponseParser()) { (data, response, error) -> () in
			let xml = data as? XMLElement
			completion(xml: xml, response: response, error: error)
		}
	}

	public func GETDATA(URL : NSURL, parameters : NSDictionary?, completion : (data : NSData?, response : NSURLResponse?, error : NSError?) -> ()) {
		GET(URL, parameters: parameters, builder: HTTPRequestBuilder(), parser: nil) { (data, response, error) -> () in
			completion(data: data as? NSData, response: response, error: error)
		}
	}

	public func POST(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			POST(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		} else {
			var error = NSError(domain: "NetKit", code: -7829, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
			completion(data: nil, response: nil, error: error)
		}
	}

	public func POST(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "POST"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func DELETE(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			DELETE(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		}
	}

	public func DELETE(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "DELETE"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func PATCH(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			PATCH(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		}
	}

	public func PATCH(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		var request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "PATCH"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}
}

extension HTTPSession {
	
	private func showNetworkActivityIndicator() {
		dispatch_async(dispatch_get_main_queue()) { () -> Void in
			UIApplication.sharedApplication().networkActivityIndicatorVisible = ++RequestCount > 0
		}
	}

	private func hideNetworkActivityIndicator() {
		dispatch_async(dispatch_get_main_queue()) { () -> Void in
			UIApplication.sharedApplication().networkActivityIndicatorVisible = --RequestCount > 0
		}
	}

	private func processResponse(response : NSURLResponse?, data : NSData?, error : NSError?, parser : ResponseParser?, completion : (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()) {
		Dump(response: response as? NSHTTPURLResponse)
//		Dump(data: data)
		var result : AnyObject? = data as AnyObject?
		var validationError = error
		switch (response, data, error, parser) {
		case let (.Some(_response), .Some(_data), .None, .Some(_parser)):
			if validateResponse(_response, error: &validationError) && _data.length > 0 && _parser.shouldParseDataForResponse(_response, error: &validationError) {
				_parser.parseData(_data, response: _response) { (parsedData, parserError) -> () in
					dispatch_async(dispatch_get_main_queue()) {
						completion(data: parsedData, response: response, error: parserError)
					}
				}
			} else {
				fallthrough
			}
		default:
			dispatch_async(dispatch_get_main_queue()) { () -> Void in
				completion(data: result, response: response, error: validationError)
			}
		}
	}

	private func validateResponse(response : NSURLResponse, error : NSErrorPointer) -> Bool {
		var result = false
		if let HTTPResponse = response as? NSHTTPURLResponse {
			result = (count(acceptedStatusCodes) > 0 || contains(acceptedStatusCodes, HTTPResponse.statusCode)) &&
				(acceptedMIMETypes.count == 0 || contains(acceptedMIMETypes, HTTPResponse.MIMEType ?? ""))
		}
		if !result && error != nil {
			error.memory
				= NSError(domain: "NetKit", code: -21384, userInfo: [NSLocalizedDescriptionKey: "Invalid Response"])
		}
		return result
	}
}

extension HTTPSession.SessionDelegate : NSURLSessionDelegate {

	func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
		if let httpSession = self.httpSession {
			httpSession.onSessionAuthenticationChallenge = nil
			httpSession.onTaskAuthenticationChallenge = nil;
		}
	}

	func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void) {
		if let _onSessionAuthenticationChallenge = httpSession?.onSessionAuthenticationChallenge {
			_onSessionAuthenticationChallenge(challenge: challenge, completion: completionHandler)
		} else {
			completionHandler(.PerformDefaultHandling, nil)
		}
	}

	func URLSessionDidFinishEventsForBackgroundURLSession(session: NSURLSession) {
		httpSession?.backgroundDelegate?.HTTPSessionDidFinishEvents(httpSession!)
	}
}

extension HTTPSession.SessionDelegate : NSURLSessionTaskDelegate {

	func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void) {
		if let _onTaskAuthenticationChallenge = httpSession?.onTaskAuthenticationChallenge {
			_onTaskAuthenticationChallenge(task: task, challenge: challenge, completion: completionHandler)
		} else {
			completionHandler(.PerformDefaultHandling, nil)
		}
	}

	func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream!) -> Void) {
		if let bodyStream = task.originalRequest.HTTPBodyStream {
			if ((bodyStream as? NSCopying) != nil) {
				completionHandler(bodyStream.copy() as! NSInputStream)
			} else {
				completionHandler(nil)
			}
		} else {
			completionHandler(nil)
		}
	}

	func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
		if let _progress = httpSession?.taskInfoMap[task.taskIdentifier]?.progress {
			dispatch_async(dispatch_get_main_queue()) {
				_progress(bytesWrittenOrRead: bytesSent, totalBytesWrittenOrRead: totalBytesSent, totalBytesExpectedToWriteOrRead: totalBytesExpectedToSend)
			}
		}
	}

	func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
		if let httpSession = self.httpSession {
			if let _taskInfo = httpSession.taskInfoMap[task.taskIdentifier] {
				switch (httpSession.isBackgroundSession, _taskInfo.completion) {
				case let (false, .Some(_completion)):
					_completion(data: _taskInfo.data, response: task.response, error: error)
				case let (true, _):
					httpSession.processResponse(task.response, data: _taskInfo.data, error: error, parser: _taskInfo.parser) { [unowned self] (data, response, error) -> Void in
						if let _backgroundDelegte = httpSession.backgroundDelegate {
							_backgroundDelegte.HTTPSession(httpSession, task: task, didCompleteWithData: data as? NSData, error: error)
						}
					}
				default:
					assert(false, "This should never happen")
				}
				httpSession.taskInfoMap.removeValueForKey(task.taskIdentifier)
			}
		}
	}
}

extension HTTPSession.SessionDelegate : NSURLSessionDataDelegate {

	func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
		var error : NSError?
		if let httpSession = self.httpSession {
			completionHandler(httpSession.validateResponse(response, error: &error) ? .Allow : .Cancel)
		} else {
			completionHandler(.Cancel)
		}
	}

	func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
		if let httpSession = self.httpSession {
			if let _taskInfo = httpSession.taskInfoMap[dataTask.taskIdentifier] {
				_taskInfo.data.appendData(data)
			} else {
				httpSession.taskInfoMap[dataTask.taskIdentifier] = HTTPSession.TaskInfo(data: data)
			}
		}
	}
}

extension HTTPSession.SessionDelegate : NSURLSessionDownloadDelegate {

	func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
		if let httpSession = self.httpSession {
			if httpSession.isBackgroundSession {
				httpSession.backgroundDownloadDelegate?.HTTPSession(httpSession, downloadTask: downloadTask, didFinishDownloadingToURL: location)
			} else if let completion = httpSession.taskInfoMap[downloadTask.taskIdentifier]?.downloadCompletion {
				completion(URL: location, response: downloadTask.response, error: nil)
				var taskInfo = httpSession.taskInfoMap[downloadTask.taskIdentifier]!
				taskInfo.completion = nil
				taskInfo.downloadCompletion = nil
				httpSession.taskInfoMap[downloadTask.taskIdentifier] = taskInfo
			}
		}
	}

	func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		if let progress = httpSession?.taskInfoMap[downloadTask.taskIdentifier]?.progress {
			dispatch_async(dispatch_get_main_queue()) {
				progress(bytesWrittenOrRead: bytesWritten, totalBytesWrittenOrRead: totalBytesWritten, totalBytesExpectedToWriteOrRead: totalBytesExpectedToWrite)
			}
		}
	}
}
