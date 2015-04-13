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
	var ptr = UnsafeMutablePointer<T>.alloc(sizeof(T))
	var val = ptr.memory
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
		var flags : SCNetworkReachabilityFlags = 0
		if SCNetworkReachabilityGetFlags(reachabilityRef.takeUnretainedValue(), &flags) == 1 {
			result = statusForFlags(flags)
		}
		return result
	}

	public var connectionRequires : Bool {
		var result = false
		var flags : SCNetworkReachabilityFlags = 0
		if SCNetworkReachabilityGetFlags(reachabilityRef.takeUnretainedValue(), &flags) == 1 {
			result = Bool(Int(flags) & kSCNetworkReachabilityFlagsConnectionRequired)
		}
		return result
	}

	private let reachabilityRef: Unmanaged<SCNetworkReachability>
	public let reachabilityType : ReachabilityType

	private init(hostAddress : UnsafePointer<sockaddr_in>, type : ReachabilityType) {
		self.reachabilityType = type
		reachabilityRef = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer<sockaddr>(hostAddress))
	}

	deinit {
		stop()
		reachabilityRef.release()
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
		var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
		return NKReachabilityStart(reachabilityRef.takeUnretainedValue(), context)
	}

	public func stop() {
		NKReachabilityStop(reachabilityRef.takeUnretainedValue())
	}

	private func statusForFlags(flags : SCNetworkReachabilityFlags) -> NetworkStatus {
		var result = NetworkStatus.NotReachable
		var options = Int(flags)
		if reachabilityType == .Internet {
			if (options & kSCNetworkReachabilityFlagsReachable) == 0 {
				return .NotReachable
			}

			if (options & kSCNetworkReachabilityFlagsConnectionRequired) == 0 {
				result = .ReachableViaWiFi
			}

			if (options & kSCNetworkReachabilityFlagsInterventionRequired) == 0 || (options & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0 {
				if (options & kSCNetworkReachabilityFlagsInterventionRequired) == 0 {
					result = .ReachableViaWiFi
				}
			}

			if (options & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN {
				result = .ReachableViaWWAN
			}
		} else {
			if (options & kSCNetworkReachabilityFlagsReachable) != 0 && (options & kSCNetworkReachabilityFlagsIsDirect) != 0 {
				result = .ReachableViaWiFi;
			}
		}
		return result
	}
}
