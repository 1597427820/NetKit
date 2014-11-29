//
//  AsyncOperation.swift
//  NetKit
//
//  Created by Mike Godenzi on 23.11.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public class AsyncOperation : NSOperation {

	private let block : (operation : AsyncOperation) -> ()
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

	public init(block : (operation : AsyncOperation) -> ()) {
		self.block = block
		super.init()
	}

	public override func start() {
		if !self.cancelled {
			self.executing = true
			dispatch_async(dispatch_get_main_queue()) { () -> Void in
				self.block(operation: self)
			}
		} else {
			stop()
		}
	}

	public func stop() {
		self.finished = true
		self.executing = false
	}
}
