//
//  NetServiceDiscoverer.swift
//  NetKit
//
//  Created by Mike Godenzi on 25.10.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public protocol NetServiceDiscovererDelegate : class {

	func netServiceDiscoverer(discoverer : NetServiceDiscoverer, shouldResolveService service : NSNetService) -> Bool
	func netServiceDiscoverer(discoverer : NetServiceDiscoverer, shouldKeepResolvedService service : NSNetService) -> Bool
	func netServiceDiscoverer(discoverer : NetServiceDiscoverer, didUpdateServiceList services : [NSNetService])
}

public class NetServiceDiscoverer : NSObject {

	public weak var delegate : NetServiceDiscovererDelegate?

	private lazy var session : HTTPSession = HTTPSession()
	private let serviceBrowser : NSNetServiceBrowser = NSNetServiceBrowser()
	private lazy var toResolve = [NSNetService]()
	private lazy var resolved = [NSNetService]()
	private var active : NSNetService?
	private var notifyUpdate = false

	public override init() {
		super.init()
		serviceBrowser.delegate = self
	}

	deinit {
		for service in toResolve {
			if service.delegate != nil && service.delegate! === self {
				service.delegate = nil
			}
		}
	}
}

extension NetServiceDiscoverer {

	public func startServiceSearch() {
		serviceBrowser.searchForServicesOfType("_http._tcp.", inDomain: "local.")
	}

	public func stopServiceSearch() {
		serviceBrowser.stop()
	}
}

extension NetServiceDiscoverer : NSNetServiceBrowserDelegate {

	public func netServiceBrowser(aNetServiceBrowser: NSNetServiceBrowser, didFindDomain domainString: String, moreComing: Bool) {
		Log("Found domain \(domainString) more coming: \(moreComing)")
	}

	public func netServiceBrowser(aNetServiceBrowser: NSNetServiceBrowser, didFindService aNetService: NSNetService, moreComing: Bool) {
		if delegate?.netServiceDiscoverer(self, shouldResolveService: aNetService) ?? true {
			toResolve.append(aNetService)
			aNetService.delegate = self
		}

		if !moreComing {
			for service in toResolve {
				service.resolveWithTimeout(10.0)
			}
		}
	}

	public func netServiceBrowser(aNetServiceBrowser: NSNetServiceBrowser, didRemoveService aNetService: NSNetService, moreComing: Bool) {
		aNetService.delegate = nil
		if let index = toResolve.indexOf(aNetService) {
			toResolve.removeAtIndex(index)
		} else if let index = resolved.indexOf(aNetService) {
			notifyUpdate = true
			resolved.removeAtIndex(index)
		}

		if !moreComing && notifyUpdate {
			notifyUpdate = false
			delegate?.netServiceDiscoverer(self, didUpdateServiceList: resolved)
		}
	}
}

extension NetServiceDiscoverer : NSNetServiceDelegate {

	public func netServiceDidResolveAddress(sender: NSNetService) {
		sender.delegate = nil

		toResolve.removeElement { $0 === sender }

		if delegate?.netServiceDiscoverer(self, shouldKeepResolvedService: sender) ?? true {
			notifyUpdate = true
			resolved.append(sender)
		}

		if toResolve.count == 0 && notifyUpdate {
			notifyUpdate = false
			delegate?.netServiceDiscoverer(self, didUpdateServiceList: resolved)
		}
	}

	public func netService(sender: NSNetService, didNotResolve errorDict: [String: NSNumber]) {
		sender.delegate = nil
		toResolve.removeElement { $0 === sender }
	}
}
