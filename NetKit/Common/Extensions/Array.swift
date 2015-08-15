//
//  Array.swift
//  NetKit
//
//  Created by Mike Godenzi on 25.10.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public func remove<C : RangeReplaceableCollectionType>(inout c : C, shouldRemove : (C.Generator.Element) -> Bool) {
	var toRemove : C.Index?

	for (index, candidate) in c.enumerate() {
		if shouldRemove(candidate) {
			toRemove = index as? C.Index
			break
		}
	}

	if let index = toRemove {
		c.removeAtIndex(index)
	}
}

extension Array {

	mutating func removeElement(condition : (Element) -> Bool) {
		remove(&self, shouldRemove: condition)
	}
}
