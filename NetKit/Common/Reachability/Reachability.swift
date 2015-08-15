//
//  Reachability.swift
//  NetKit
//
//  Created by Mike Godenzi on 26.10.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation
import SystemConfiguration

private func blankOf<T>(type: T.Type) -> T {
	let ptr = UnsafeMutablePointer<T>.alloc(sizeof(T))
	let val = ptr.memory
	ptr.destroy()
	return val
}

public let NetworkReachabilityChangedNotification = "NetworkReachabilityChangedNotification"

public enum ReachabilityType {
	case Internet, LocalWiFi
}

public class Reachability {

	public enum NetworkStatus {
		case NotReachable, ReachableViaWiFi, ReachableViaWWAN
	}

	public var currentStatus : NetworkStatus {
		var result = NetworkStatus.NotReachable
		var flags : SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
		if SCNetworkReachabilityGetFlags(reachability, &flags) == true {
			result = statusForFlags(flags)
		}
		return result
	}

	public var connectionRequires : Bool {
		var result = false
		var flags : SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
		if SCNetworkReachabilityGetFlags(reachability, &flags) == true {
			result = flags.contains(SCNetworkReachabilityFlags.ConnectionRequired)
		}
		return result
	}

	private let reachability: SCNetworkReachability
	public let reachabilityType : ReachabilityType

	private init(hostAddress : UnsafePointer<sockaddr_in>, type : ReachabilityType) {
		reachabilityType = type
		reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer<sockaddr>(hostAddress))!
	}

	deinit {
		stop()
	}

	public convenience init(type : ReachabilityType) {
		var address = blankOf(sockaddr_in)
		address.sin_len = UInt8(sizeof(sockaddr_in))
		address.sin_family = sa_family_t(AF_INET)
		if type == .LocalWiFi {
			address.sin_addr.s_addr = CFSwapInt32HostToBig(0xA9FE0000)
		}
		self.init(hostAddress: &address, type: type)
	}

	public func start() -> Bool {
		let context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
		return NKReachabilityStart(reachability, context)
	}

	public func stop() {
		NKReachabilityStop(reachability)
	}

	private func statusForFlags(flags : SCNetworkReachabilityFlags) -> NetworkStatus {
		var result = NetworkStatus.NotReachable
		if reachabilityType == .Internet {
			if !flags.contains(SCNetworkReachabilityFlags.Reachable) {
				return .NotReachable
			}

			if !flags.contains(SCNetworkReachabilityFlags.ConnectionRequired) {
				result = .ReachableViaWiFi
			}

			if !flags.contains(SCNetworkReachabilityFlags.InterventionRequired) || flags.contains(SCNetworkReachabilityFlags.ConnectionOnTraffic) {
				if !flags.contains(SCNetworkReachabilityFlags.InterventionRequired) {
					result = .ReachableViaWiFi
				}
			}

			if flags == SCNetworkReachabilityFlags.IsWWAN {
				result = .ReachableViaWWAN
			}
		} else {
			if flags.contains(SCNetworkReachabilityFlags.Reachable) && flags.contains(SCNetworkReachabilityFlags.IsDirect) {
				result = .ReachableViaWiFi;
			}
		}
		return result
	}
}
