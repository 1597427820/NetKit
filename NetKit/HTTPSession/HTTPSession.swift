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

public protocol JSONInitializable {
	init(JSON : NSDictionary)
}

public func map<T : JSONInitializable>(JSONs : [NSDictionary]) -> [T] {
	return JSONs.map {T(JSON: $0)}
}

public protocol HTTPSessionBackgroundDelegate : class {
	func HTTPSessionDidFinishEvents(session : NetKit.HTTPSession)
	func HTTPSession(session : NetKit.HTTPSession, task : NSURLSessionTask, didCompleteWithData data : NSData?, error : NSError?)
}

public protocol HTTPSessionBackgroundDownloadDelegate : class {
	func HTTPSession(session : NetKit.HTTPSession, downloadTask : NSURLSessionDownloadTask, didFinishDownloadingToURL URL: NSURL)
}

public class HTTPSession : NSObject {

	public typealias ProgressBlock = (bytesWrittenOrRead : Int64, totalBytesWrittenOrRead : Int64, totalBytesExpectedToWriteOrRead : Int64) -> ();
	public typealias CompletionBlock = (data : AnyObject?, response : NSURLResponse?, error : NSError?) -> ()
	public typealias DataCompletionBlock = (data : NSData?, response : NSURLResponse?, error : NSError?) -> ()
	public typealias DownloadCompletionBlock = (URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ()
	public typealias AuthenticationChallengeCompletionBlock = (disposition : NSURLSessionAuthChallengeDisposition, credential : NSURLCredential) -> ()
	public typealias SessionAuthenticationChallengeBlock = (challenge : NSURLAuthenticationChallenge, completion : AuthenticationChallengeCompletionBlock) -> ()
	public typealias TaskAuthenticationChallengeBlock = (task : NSURLSessionTask, challenge : NSURLAuthenticationChallenge, completion : AuthenticationChallengeCompletionBlock) -> ()

	public var acceptedStatusCodes = Range(200..<300)
	public var acceptedMIMETypes : [String] = []
	public var onSessionAuthenticationChallenge : SessionAuthenticationChallengeBlock?
	public var onTaskAuthenticationChallenge : TaskAuthenticationChallengeBlock?
	public weak var backgroundDelegate : HTTPSessionBackgroundDelegate?
	public weak var backgroundDownloadDelegate : HTTPSessionBackgroundDownloadDelegate?

	private struct TaskInfo {

		var data = NSMutableData()
		var parser : ResponseParser?
		var progress : ProgressBlock?
		var completion : CompletionBlock?
		var downloadCompletion : DownloadCompletionBlock?

		init() {}

		init(data : NSData) {
			self.data.appendData(data)
		}
	}
	private var taskInfoMap = [Int:TaskInfo]()

	private var configuration : NSURLSessionConfiguration
	private lazy var session : NSURLSession = NSURLSession(configuration: self.configuration, delegate: self, delegateQueue: nil)
	private var isBackgroundSession : Bool {
		var identifier : String? = self.configuration.identifier
		return  identifier != nil
	}

	required public init(configuration : NSURLSessionConfiguration?) {
		self.configuration = configuration ?? NSURLSessionConfiguration.defaultSessionConfiguration()
		super.init()
	}

	convenience public override init() {
		self.init(configuration: nil)
	}
}

extension HTTPSession {

	public func startRequest(request : NSURLRequest, parser : ResponseParser?, completion : CompletionBlock) {
		Dump(request: request)
		showNetworkActivityIndicator()
		let task = session.dataTaskWithRequest(request) { [unowned self] (data, response, error) -> Void in
			self.hideNetworkActivityIndicator();
			self.processResponse(response, data: data, error: error, parser: parser, completion: completion)
		}
		task.resume()
	}

	public func startRequest(request : NSURLRequest, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var error : NSError?
		var builtRequest : NSURLRequest? = request;
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

	public func downloadRequest(request : NSURLRequest, parameters : NSDictionary?, builder : RequestBuilder?, progress : ProgressBlock?, completion : DownloadCompletionBlock) {
		var error : NSError?
		var builtRequest = builder?.buildRequest(request, parameters: parameters, error: &error);

		if let _builtRequest = builtRequest {
			var completionHanlder : DownloadCompletionBlock? = { [unowned self] (URL, response, error) in
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

	public func resumeDownloadWithData(data : NSData, progress : ProgressBlock?, completion : DownloadCompletionBlock) {
		var completionHanlder : DownloadCompletionBlock? = { [unowned self] (URL, response, error) in
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

	public func invalidateAndCancel() {
		session.invalidateAndCancel()
	}
}

extension HTTPSession {

	public func GET(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			GET(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		} else {
			var error = NSError(domain: "NetKit", code: -7829, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
			completion(data: nil, response: nil, error: error)
		}
	}

	public func GET(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "GET"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func GETJSON(#URLString : String, parameters : NSDictionary?, completion : CompletionBlock) {
		GET(URLString: URLString, parameters: parameters, builder: JSONRequestBuilder(), parser: JSONResponseParser(), completion: completion)
	}

	public func GETJSON(URL : NSURL, parameters : NSDictionary?, completion : CompletionBlock) {
		GET(URL, parameters: parameters, builder: JSONRequestBuilder(), parser: JSONResponseParser(), completion: completion)
	}

	public func GETXML(#URLString : String, parameters : NSDictionary?, completion : CompletionBlock) {
		GET(URLString: URLString, parameters: parameters, builder: HTTPRequestBuilder(), parser: XMLResponseParser(), completion: completion)
	}

	public func GETXML(URL : NSURL, parameters : NSDictionary?, completion : CompletionBlock) {
		GET(URL, parameters: parameters, builder: HTTPRequestBuilder(), parser: XMLResponseParser(), completion: completion)
	}

	public func GETDATA(URL : NSURL, parameters : NSDictionary?, completion : DataCompletionBlock) {
		GET(URL, parameters: parameters, builder: HTTPRequestBuilder(), parser: nil) { (data, response, error) -> () in
			completion(data: data as? NSData, response: response, error: error)
		}
	}

	public func POST(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			POST(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		} else {
			var error = NSError(domain: "NetKit", code: -7829, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
			completion(data: nil, response: nil, error: error)
		}
	}

	public func POST(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "POST"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func DELETE(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			DELETE(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		}
	}

	public func DELETE(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "DELETE"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func PATCH(#URLString : String, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
		var URL = NSURL(string: URLString)
		if let _URL = URL {
			PATCH(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		}
	}

	public func PATCH(URL : NSURL, parameters : NSDictionary?, builder : RequestBuilder?, parser : ResponseParser?, completion : CompletionBlock) {
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

	private func processResponse(response : NSURLResponse?, data : NSData?, error : NSError?, parser : ResponseParser?, completion : CompletionBlock) {
		Dump(response: response as? NSHTTPURLResponse)
		Dump(data: data)
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
			completion(data: result, response: response, error: validationError)
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

extension HTTPSession : NSURLSessionDelegate {

	public func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
		onSessionAuthenticationChallenge = nil;
		onTaskAuthenticationChallenge = nil;
	}

	public func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void) {
		if let _onSessionAuthenticationChallenge = onSessionAuthenticationChallenge {
			_onSessionAuthenticationChallenge(challenge: challenge, completion: completionHandler)
		} else {
			completionHandler(.PerformDefaultHandling, nil)
		}
	}

	public func URLSessionDidFinishEventsForBackgroundURLSession(session: NSURLSession) {
		backgroundDelegate?.HTTPSessionDidFinishEvents(self)
	}
}

extension HTTPSession : NSURLSessionTaskDelegate {

	public func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void) {
		if let _onTaskAuthenticationChallenge = onTaskAuthenticationChallenge {
			_onTaskAuthenticationChallenge(task: task, challenge: challenge, completion: completionHandler)
		} else {
			completionHandler(.PerformDefaultHandling, nil)
		}
	}

	public func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream!) -> Void) {
		if let bodyStream = task.originalRequest.HTTPBodyStream {
			if (bodyStream as? NSCopying != nil) {
				completionHandler(bodyStream.copy() as NSInputStream)
			} else {
				completionHandler(nil)
			}
		} else {
			completionHandler(nil)
		}
	}

	public func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
		let taskInfo = taskInfoMap[task.taskIdentifier]
		if let _progress = taskInfo?.progress {
			dispatch_async(dispatch_get_main_queue()) {
				_progress(bytesWrittenOrRead: bytesSent, totalBytesWrittenOrRead: totalBytesSent, totalBytesExpectedToWriteOrRead: totalBytesExpectedToSend)
			}
		}
	}

	public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
		let taskInfo = taskInfoMap[task.taskIdentifier]
		if let _taskInfo = taskInfo {
			switch (isBackgroundSession, _taskInfo.completion) {
			case let (false, .Some(_completion)):
				_completion(data: _taskInfo.data, response: task.response, error: error)
			case let (true, _):
				processResponse(task.response, data: _taskInfo.data, error: error, parser: _taskInfo.parser) { [unowned self] (data, response, error) -> Void in
					if let _backgroundDelegte = self.backgroundDelegate {
						_backgroundDelegte.HTTPSession(self, task: task, didCompleteWithData: data as? NSData, error: error)
					}
				}
			default:
				assert(false, "This should never happen")
			}
			taskInfoMap.removeValueForKey(task.taskIdentifier)
		}
	}
}

extension HTTPSession : NSURLSessionDataDelegate {

	public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
		var error : NSError?
		completionHandler(validateResponse(response, error: &error) ? .Allow : .Cancel)
	}

	public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
		let taskInfo = taskInfoMap[dataTask.taskIdentifier]
		if let _taskInfo = taskInfo {
			_taskInfo.data.appendData(data)
		} else {
			taskInfoMap[dataTask.taskIdentifier] = TaskInfo(data: data)
		}
	}
}

extension HTTPSession : NSURLSessionDownloadDelegate {

	public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
		if isBackgroundSession {
			backgroundDownloadDelegate?.HTTPSession(self, downloadTask: downloadTask, didFinishDownloadingToURL: location)
		} else if let completion = taskInfoMap[downloadTask.taskIdentifier]?.downloadCompletion {
			completion(URL: location, response: downloadTask.response, error: nil)
			var taskInfo = taskInfoMap[downloadTask.taskIdentifier]!
			taskInfo.completion = nil
			taskInfo.downloadCompletion = nil
			taskInfoMap[downloadTask.taskIdentifier] = taskInfo
		}
	}

	public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		if let progress = taskInfoMap[downloadTask.taskIdentifier]?.progress {
			dispatch_async(dispatch_get_main_queue()) {
				progress(bytesWrittenOrRead: bytesWritten, totalBytesWrittenOrRead: totalBytesWritten, totalBytesExpectedToWriteOrRead: totalBytesExpectedToWrite)
			}
		}
	}
}
