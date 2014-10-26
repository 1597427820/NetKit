//
//  Reachability.h
//  NetKit
//
//  Created by Mike Godenzi on 26.10.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

@import Foundation;
@import SystemConfiguration;

static NSString * const NKNetworkReachabilityChangedNotification = @"NetworkReachabilityChangedNotification";

BOOL NKReachabilityStart(SCNetworkReachabilityRef reachabilityRef, SCNetworkReachabilityContext context);
void NKReachabilityStop(SCNetworkReachabilityRef reachabilityRef);
