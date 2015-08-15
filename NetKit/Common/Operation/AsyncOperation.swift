//
//  AsyncOperation.swift
//  NetKit
//
//  Created by Mike Godenzi on 23.11.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public class AsyncOperation : NSOperation {

	public static let AsyncOperationErrorDomain = "AsyncOperationError"
	public enum AsyncOperationError : Int {
		case Unknown = -1
		case Cancelled
		case DependencyError
	}

	private let block : ((operation : AsyncOperation) -> ())?
	override public var asynchronous : Bool {
		return true
	}

	private var isExecuting : Bool = false
	override public var executing : Bool {
		get {
			return isExecuting
		}
		set {
			self.willChangeValueForKey("isExecuting")
			isExecuting = newValue
			self.didChangeValueForKey("isExecuting")
		}
	}

	private var isFinished : Bool = false
	override public var finished : Bool {
		get {
			return isFinished
		}
		set {
			self.willChangeValueForKey("isFinished")
			isFinished = newValue
			self.didChangeValueForKey("isFinished")
		}
	}

	public var error : NSError?
	public var operationWillFinishHandler : ((AsyncOperation) -> Void)?
	public var operationDidFinishHandler : ((AsyncOperation) -> Void)?

	public init(block : ((operation : AsyncOperation) -> ())? = nil) {
		self.block = block
		super.init()
	}

	public override func start() {

		guard !self.cancelled else {
			stop(NSError(code: .Cancelled, message: "Operation was cancelled"))
			return
		}

		guard canExecute() else {
			stop(error ?? NSError(code: .DependencyError, message: "Dependent operation terminated with error"))
			return
		}

		self.executing = true
		perform()
	}

	public func stop(error : NSError? = nil) {
		self.error = error
		operationWillFinishHandler?(self)
		self.finished = true
		self.executing = false
		operationDidFinishHandler?(self)
	}

	public func perform() {
		guard let block = self.block else {
			stop()
			return
		}
		block(operation: self)
	}

	public func willEnqueueDependantOperations(operations : [NSOperation]) {
	}

	private func canExecute() -> Bool {
		var result = true
		let operations = dependencies
		for op in operations {
			if let asyncOP = op as? AsyncOperation where asyncOP.error != nil {
				result = false
				error = asyncOP.error
				break
			}
		}
		return result
	}
}

extension NSError {

	private convenience init(code : AsyncOperation.AsyncOperationError, message: String) {
		self.init(domain: AsyncOperation.AsyncOperationErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
	}
}
