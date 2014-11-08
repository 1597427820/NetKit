//
//  JSON.swift
//  NetKit
//
//  Created by Mike Godenzi on 04.11.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public protocol JSONInitializable {
	init(JSON : NSDictionary)
}

public func map<T : JSONInitializable>(JSONs : [NSDictionary]) -> [T] {
	return JSONs.map { T(JSON: $0) }
}
