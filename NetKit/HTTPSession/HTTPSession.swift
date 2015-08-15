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
		let identifier : String? = self.configuration.identifier
		return  identifier != nil
	}

	required public init(configuration : NSURLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()) {
		self.configuration = configuration
	}

	deinit {
		session.invalidateAndCancel()
	}
}

extension HTTPSession {

	public func startRequest<P : ResponseParser>(request : NSURLRequest, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		Dump(request: request)
		Dump(data: request.HTTPBody)
		showNetworkActivityIndicator()
		let task = session.dataTaskWithRequest(request) { [weak self] (data, response, error) -> Void in
			hideNetworkActivityIndicator();
			if let selfStrong = self {
				selfStrong.processResponse(response, data: data, error: error, parser: parser, completion: completion)
			} else {
				let error = NSError(domain: "NetKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown Error"])
				completion(data: nil, response: nil, error: error)
			}
		}
		task.resume()
	}

	public func startRequest<P : ResponseParser>(request : NSURLRequest, parameters : NSDictionary?, builder : RequestBuilder?, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		var error : NSError?
		var builtRequest : NSURLRequest? = request

		if let builder = builder {
			do {
				builtRequest = try builder.buildRequest(request, parameters: parameters)
			} catch let buildError {
				builtRequest = nil
				error = buildError as NSError
			}
		}

		if let builtRequest = builtRequest {
			startRequest(builtRequest, parser: parser, completion: completion)
		} else {
			dispatch_async(dispatch_get_main_queue()) {
				completion(data: nil, response: nil, error: error)
			}
		}
	}

	public func downloadRequest(request : NSURLRequest, parameters : NSDictionary?, builder : RequestBuilder?, progress : ((bytesWrittenOrRead : Int64, totalBytesWrittenOrRead : Int64, totalBytesExpectedToWriteOrRead : Int64) -> ())?, completion : (URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ()) {
		var error : NSError?
		var builtRequest : NSURLRequest? = request

		if let builder = builder {
			do {
				builtRequest = try builder.buildRequest(request, parameters: parameters);
			} catch let builtError {
				builtRequest = nil
				error = builtError as NSError
			}
		}

		if let builtRequest = builtRequest {
			var completionHanlder : ((URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ())? = { [weak self] (URL, response, var error) in
				guard let selfStrong = self else {
					completion(URL: nil, response: nil, error: error)
					return
				}
				if let response = response where error == nil {
					do {
						try selfStrong.validateResponse(response)
					} catch let validationError {
						error = validationError as NSError
					}
				}
				completion(URL: URL, response: response, error: error)
			}
			var taskInfo : TaskInfo? = nil
			if isBackgroundSession || progress != nil {
				taskInfo = TaskInfo()
				taskInfo!.progress = progress
				taskInfo!.downloadCompletion = completionHanlder
				completionHanlder = nil
			}
			Dump(request: builtRequest)
			// FIXME: completionHandler is force unwrapped because for some reason it cannot be nil anymore, probably an error in the Apple header
			let task = session.downloadTaskWithRequest(builtRequest, completionHandler: completionHanlder!)
			if let taskInfo = taskInfo {
				session.delegateQueue.addOperationWithBlock { [unowned self] in
					self.taskInfoMap[task.taskIdentifier] = taskInfo
				}
			}
			task.resume()
		} else {
			completion(URL: nil, response: nil, error: error)
		}
	}

	public func resumeDownloadWithData(data : NSData, progress : ((bytesWrittenOrRead : Int64, totalBytesWrittenOrRead : Int64, totalBytesExpectedToWriteOrRead : Int64) -> ())?, completion : (URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ()) {
		var completionHanlder : ((URL : NSURL?, response : NSURLResponse?, error : NSError?) -> ())? = { [weak self] (URL, response, var error) in
			guard let selfStrong = self else {
				completion(URL: nil, response: nil, error: error)
				return
			}
			if let response = response where error == nil {
				do {
					try selfStrong.validateResponse(response)
				} catch let validationError {
					error = validationError as NSError
				}
			}
			completion(URL: URL, response: response, error: error)
		}
		var taskInfo : TaskInfo? = nil
		if isBackgroundSession || progress != nil {
			taskInfo = TaskInfo()
			taskInfo!.progress = progress
			taskInfo!.downloadCompletion = completionHanlder
			completionHanlder = nil
		}
		let task = session.downloadTaskWithResumeData(data, completionHandler: completionHanlder!)
		if let taskInfo = taskInfo {
			session.delegateQueue.addOperationWithBlock { [unowned self] in
				self.taskInfoMap[task.taskIdentifier] = taskInfo
			}
		}
		task.resume()
	}

	public func resetWithCompletion(completion : () -> ()) {
		session.resetWithCompletionHandler(completion)
	}
}

extension HTTPSession {

	public func startRequest(request : NSURLRequest, completion : (data : NSData?, response : NSURLResponse?, error : NSError?) -> ()) {
		startRequest(request, parser: DataResponseParser(), completion: completion)
	}

	public func startRequest(request : NSURLRequest, parameters : NSDictionary?, builder : RequestBuilder?, completion : (data : NSData?, response : NSURLResponse?, error : NSError?) -> ()) {
		startRequest(request, parameters: parameters, builder: builder, parser: DataResponseParser(), completion: completion)
	}
}

extension HTTPSession {

	public func GET<P : ResponseParser>(URLString URLString : String, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let URL = NSURL(string: URLString)
		if let _URL = URL {
			GET(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		} else {
			let error = NSError(domain: "NetKit", code: -7829, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
			completion(data: nil, response: nil, error: error)
		}
	}

	public func GET<P : ResponseParser>(URL : NSURL, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "GET"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func GETDATA(URL : NSURL, parameters : NSDictionary? = nil, completion : (data : NSData?, response : NSURLResponse?, error : NSError?) -> ()) {
		GET(URL, parameters: parameters, builder: HTTPRequestBuilder(), parser: DataResponseParser()) { (data, response, error) -> () in
			completion(data: data, response: response, error: error)
		}
	}

	public func POST<P : ResponseParser>(URLString URLString : String, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let URL = NSURL(string: URLString)
		if let _URL = URL {
			POST(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		} else {
			let error = NSError(domain: "NetKit", code: -7829, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
			completion(data: nil, response: nil, error: error)
		}
	}

	public func POST<P : ResponseParser>(URL : NSURL, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "POST"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func DELETE<P : ResponseParser>(URLString URLString : String, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let URL = NSURL(string: URLString)
		if let _URL = URL {
			DELETE(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		}
	}

	public func DELETE<P : ResponseParser>(URL : NSURL, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "DELETE"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}

	public func PATCH<P : ResponseParser>(URLString URLString : String, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let URL = NSURL(string: URLString)
		if let _URL = URL {
			PATCH(_URL, parameters: parameters, builder: builder, parser: parser, completion: completion)
		}
	}

	public func PATCH<P : ResponseParser>(URL : NSURL, parameters : NSDictionary? = nil, builder : RequestBuilder? = nil, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		let request = NSMutableURLRequest(URL: URL)
		request.HTTPMethod = "PATCH"
		startRequest(request, parameters: parameters, builder: builder, parser: parser, completion: completion)
	}
}

extension HTTPSession {

	private func processResponse<P : ResponseParser>(response : NSURLResponse?, data : NSData?, var error : NSError?, parser : P, completion : (data : P.Parser.ResultType?, response : NSURLResponse?, error : NSError?) -> ()) {
		Dump(response: response as? NSHTTPURLResponse)
//		Dump(data: data)
		if let response = response, let data = data where error == nil {
			do {
				try validateResponse(response)
				if data.length > 0 {
					try parser.shouldParseDataForResponse(response)
					parser.parseData(data, response: response) { (result, error) -> () in
						dispatch_async(dispatch_get_main_queue()) {
							completion(data: result, response: response, error: error)
						}
					}
					return
				}
			} catch let validationError {
				error = validationError as NSError
			}
		}
		dispatch_async(dispatch_get_main_queue()) { () -> Void in
			completion(data: nil, response: response, error: error)
		}
	}

	private func validateResponse(response : NSURLResponse) throws {
		var valid = false
		if let HTTPResponse = response as? NSHTTPURLResponse {
			valid = (acceptedStatusCodes.count > 0 || acceptedStatusCodes.contains(HTTPResponse.statusCode)) &&
				(acceptedMIMETypes.count == 0 || acceptedMIMETypes.contains(HTTPResponse.MIMEType ?? ""))
		}
		if !valid {
			throw NSError(domain: "NetKit", code: -21384, userInfo: [NSLocalizedDescriptionKey: "Invalid Response"])
		}
	}
}

extension HTTPSession.SessionDelegate : NSURLSessionDelegate {

	func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
		if let httpSession = self.httpSession {
			httpSession.onSessionAuthenticationChallenge = nil
			httpSession.onTaskAuthenticationChallenge = nil;
		}
	}

	func URLSession(session: NSURLSession, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
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

	func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
		if let _onTaskAuthenticationChallenge = httpSession?.onTaskAuthenticationChallenge {
			_onTaskAuthenticationChallenge(task: task, challenge: challenge, completion: completionHandler)
		} else {
			completionHandler(.PerformDefaultHandling, nil)
		}
	}

	func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream?) -> Void) {
		if let bodyStream = task.originalRequest?.HTTPBodyStream {
			if ((bodyStream as? NSCopying) != nil) {
				completionHandler((bodyStream.copy() as! NSInputStream))
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
		guard let httpSession = self.httpSession, let taskInfo = httpSession.taskInfoMap[task.taskIdentifier] else { return }
		if httpSession.isBackgroundSession {
			httpSession.processResponse(task.response, data: taskInfo.data, error: error, parser: DataResponseParser()) { (data, response, error) -> Void in
				if let backgroundDelegte = httpSession.backgroundDelegate {
					backgroundDelegte.HTTPSession(httpSession, task: task, didCompleteWithData: data, error: error)
				}
			}
		} else if let completion = taskInfo.completion {
			completion(data: taskInfo.data, response: task.response, error: error)
		}
		httpSession.taskInfoMap.removeValueForKey(task.taskIdentifier)
	}
}

extension HTTPSession.SessionDelegate : NSURLSessionDataDelegate {

	func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
		var disposition = NSURLSessionResponseDisposition.Cancel
		if let httpSession = httpSession {
			do {
				try httpSession.validateResponse(response)
				disposition = .Allow
			} catch {}
		}
		completionHandler(disposition)
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
