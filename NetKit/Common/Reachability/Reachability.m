//
//  Reachability.m
//  NetKit
//
//  Created by Mike Godenzi on 26.10.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

#import "Reachability.h"

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void * info) {
#pragma unused (target, flags)
	//We're on the main RunLoop, so an NSAutoreleasePool is not necessary, but is added defensively
	// in case someon uses the Reachablity object in a different thread.
	@autoreleasepool {
		// Post a notification to notify the client that the network reachability changed.
		[[NSNotificationCenter defaultCenter] postNotificationName:NKNetworkReachabilityChangedNotification object:nil];
	}
}

BOOL NKReachabilityStart(SCNetworkReachabilityRef reachabilityRef, SCNetworkReachabilityContext context) {
	return SCNetworkReachabilitySetCallback(reachabilityRef, ReachabilityCallback, &context) &&
	SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

void NKReachabilityStop(SCNetworkReachabilityRef reachabilityRef) {
	SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}
