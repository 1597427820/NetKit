//
//  JSON.swift
//  TurboKit
//
//  Created by Mike Godenzi on 12.05.15.
//  Copyright (c) 2015 Mike Godenzi. All rights reserved.
//

import Foundation

public protocol JSONConvertible {
	func toJSON() -> JSON
}

public protocol JSONInitializable {
	init?(_ json : JSON)
}

public enum JSON : Equatable {

	case Array([JSON])
	case Object([Swift.String:JSON])
	case String(Swift.String)
	case Integer(Int)
	case Real(Double)
	case Boolean(Bool)
	case Null

	public init(_ obj : JSONConvertible) {
		self = obj.toJSON()
	}

	public init(data : NSData) throws {
		if let obj = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as? JSONConvertible {
			self = obj.toJSON()
		} else {
			throw NSError(domain: "JSON", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
		}
	}

	public func value<T>() -> T? {
		switch self {
		case let .String(v as T):
			return v
		case let .Array(v as T):
			return v
		case let .Object(v as T):
			return v
		case let .Integer(v as T):
			return v
		case let .Real(v as T):
			return v
		case let .Boolean(v as T):
			return v
		default:
			return nil
		}
	}

	public subscript(key : Swift.String) -> JSON {
		get {
			if let d : [Swift.String:JSON] = value() {
				return d[key] ?? .Null
			}
			return .Null
		}
	}

	public subscript(index : Int) -> JSON {
		get {
			if let a : [JSON] = value() {
				return index < a.count ? a[index] : .Null
			}
			return .Null
		}
	}
}

extension JSON : StringLiteralConvertible {

	public typealias ExtendedGraphemeClusterLiteralType = Swift.String
	public typealias UnicodeScalarLiteralType = Swift.String

	public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
		self = .String(value)
	}

	public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
		self = .String(value)
	}

	public init(stringLiteral value: StringLiteralType) {
		self = .String(value)
	}
}

extension JSON : ArrayLiteralConvertible {

	public typealias Element = JSON

	public init(arrayLiteral elements: Element...) {
		self = .Array(elements)
	}
}

extension JSON : DictionaryLiteralConvertible {

	public typealias Key = Swift.String
	public typealias Value = JSON

	public init(dictionaryLiteral elements: (Key, Value)...) {
		var dictionary : [Key:Value] = [Key:Value]()
		for (key, value) in elements {
			dictionary[key] = value
		}
		self = .Object(dictionary)
	}

	init(_ dictionary : [Key:Value]) {
		self = .Object(dictionary)
	}
}

extension JSON : IntegerLiteralConvertible {

	public init(integerLiteral value: IntegerLiteralType) {
		self = .Integer(value)
	}
}

extension JSON : FloatLiteralConvertible {

	public init(floatLiteral value: FloatLiteralType) {
		self = .Real(value)
	}
}

extension JSON : BooleanLiteralConvertible {

	public init(booleanLiteral value: BooleanLiteralType) {
		self = .Boolean(value)
	}
}

extension JSON : NilLiteralConvertible {

	public init(nilLiteral: ()) {
		self = .Null
	}
}

extension JSON : SequenceType {

	public func generate() -> AnyGenerator<(Swift.String,JSON)> {
		switch self {
		case let .Array(v):
			var nextIndex = 0
			return anyGenerator {
				if nextIndex < v.count {
					return ("\(nextIndex)", v[nextIndex++])
				}
				return nil
			}
		case let .Object(v):
			var nextIndex = v.startIndex
			return anyGenerator {
				if nextIndex < v.endIndex {
					return v[nextIndex++]
				}
				return nil
			}
		default:
			return anyGenerator {return nil}
		}
	}
}

extension JSON : CustomStringConvertible {

	public var description : Swift.String {
		switch self {
		case let .String(v):
			return v
		case let .Array(v):
			return v.description
		case let .Object(v):
			return v.description
		case let .Integer(v):
			return v.description
		case let .Real(v):
			return v.description
		case let .Boolean(v):
			return v.description
		default:
			return "Null"
		}
	}
}

extension JSON : CustomDebugStringConvertible {

	public var debugDescription : Swift.String {
		switch self {
		case let .String(v):
			return "String(\(v))"
		case let .Array(v):
			return "Array(\(v.debugDescription))"
		case let .Object(v):
			return "Object(\(v.debugDescription))"
		case let .Integer(v):
			return "Integer(\(v.description))"
		case let .Real(v):
			return "Real(\(v.description))"
		case let .Boolean(v):
			return "Boolean(\(v.description))"
		default:
			return "Null"
		}
	}
}

extension JSON {

	public func map<T>(block : (JSON) -> T?) -> [T]? {
		var result = [T]()
		for (_, v) in self {
			if let t = block(v) {
				result.append(t)
			}
		}
		return result.count > 0 ? result : nil
	}
}

public func ==(lhs: JSON, rhs: JSON) -> Bool {
	switch (lhs, rhs) {
	case let (.Object(v1), .Object(v2)):
		return v1 == v2
	case let (.Array(v1), .Array(v2)):
		return v1 == v2
	case let (.String(v1), .String(v2)):
		return v1 == v2
	case let (.Integer(v1), .Integer(v2)):
		return v1 == v2
	case let (.Real(v1), .Real(v2)):
		return v1 == v2
	case let (.Boolean(v1), .Boolean(v2)):
		return v1 == v2
	case (.Null, .Null):
		return true
	default:
		return false
	}
}

extension Int : JSONConvertible, JSONInitializable {

	public init?(_ json : JSON) {
		if let i : Int = json.value() {
			self = i
		} else {
			return nil
		}
	}

	public func toJSON() -> JSON {
		return .Integer(self)
	}
}

extension Double : JSONConvertible, JSONInitializable {

	public init?(_ json : JSON) {
		if let d : Double = json.value() {
			self = d
		} else {
			return nil
		}
	}

	public func toJSON() -> JSON {
		return .Real(self)
	}
}

extension Float : JSONInitializable {

	public init?(_ json: JSON) {
		if let d : Double = json.value() {
			self = Float(d)
		} else {
			return nil
		}
	}
}

extension Bool : JSONConvertible, JSONInitializable {

	public init?(_ json : JSON) {
		if let b : Bool = json.value() {
			self = b
		} else {
			return nil
		}
	}

	public func toJSON() -> JSON {
		return .Boolean(self)
	}
}

extension NSNumber : JSONConvertible {

	public func toJSON() -> JSON {
		let type = String.fromCString(self.objCType)!
		switch type {
		case "f", "d":
			return .Real(self.doubleValue)
		case "c":
			return .Boolean(self.boolValue)
		default:
			return .Integer(self.integerValue)
		}
	}
}

extension Array : JSONConvertible {

	public func toJSON() -> JSON {
		let jsonArray : [JSON] = self.map { element in
			if let jc = element as? JSONConvertible {
				return jc.toJSON()
			}
			return .Null
		}
		return .Array(jsonArray)
	}
}

extension NSArray : JSONConvertible {

	public func toJSON() -> JSON {
		var jsonArray = [JSON]()
		jsonArray.reserveCapacity(self.count)

		for e in self {
			if let jc = e as? JSONConvertible {
				jsonArray.append(jc.toJSON())
			} else {
				jsonArray.append(.Null)
			}
		}

		return .Array(jsonArray)
	}
}

extension Dictionary : JSONConvertible {

	public func toJSON() -> JSON {
		var jsonDictionary = [String:JSON]()
		for (key, value) in self {
			if let s = key as? String {
				if let j = value as? JSONConvertible {
					jsonDictionary[s] = j.toJSON()
				} else {
					jsonDictionary[s] = .Null
				}
			}
		}
		return .Object(jsonDictionary)
	}
}

extension NSDictionary : JSONConvertible {

	public func toJSON() -> JSON {
		var jsonDictionary = [String:JSON]()
		for (key, value) in self {
			if let s = key as? String {
				if let j = value as? JSONConvertible {
					jsonDictionary[s] = j.toJSON()
				} else {
					jsonDictionary[s] = .Null
				}
			}
		}
		return .Object(jsonDictionary)
	}
}

extension String : JSONConvertible, JSONInitializable {

	public init?(_ json : JSON) {
		if let v : String = json.value() {
			self = v
		} else {
			return nil
		}
	}

	public func toJSON() -> JSON {
		return .String(self)
	}
}

extension NSString : JSONConvertible {

	public func toJSON() -> JSON {
		return .String(String(self))
	}
}

prefix operator <? {}
prefix operator <! {}

public prefix func <? <T : JSONInitializable> (json : JSON) -> T? {
	return T(json)
}

public prefix func <! <T : JSONInitializable> (json : JSON) -> T {
	return (<?json)!
}

public prefix func <? <T : JSONInitializable> (json : JSON) -> [T]? {
	if let jsonArray : [JSON] = json.value() {
		var result = [T]()
		result.reserveCapacity(jsonArray.count)
		for value in jsonArray {
			if let e : T = <?value {
				result.append(e)
			}
		}
		return result.count > 0 ? result : nil
	}
	return nil
}

public prefix func <! <T : JSONInitializable> (json : JSON) -> [T] {
	let result : [T]? = <?json
	return result!
}

public prefix func <? <T : JSONInitializable> (json : JSON) -> [String:T]? {
	if let jsonDict : [String:JSON] = json.value() {
		var result = [String:T](minimumCapacity: jsonDict.count)
		for (k, v) in jsonDict {
			if let value : T = <?v {
				result[k] = value
			} else {
				return nil
			}
		}
		return result
	}
	return nil
}

public prefix func <! <T : JSONInitializable> (json : JSON) -> [String:T] {
	let result : [String:T]? = <?json
	return result!
}

public class JSONDataParser : DataParser {

	public typealias ResultType = JSON

	required public init() {}

	public func parseData(data: NSData) throws -> ResultType {
		if let j = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as? JSONConvertible {
			return JSON(j)
		} else {
			throw NSError(domain: "JSONDataParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
		}
	}
}

public class JSONResponseParser : HTTPResponseParser<JSONDataParser> {

	public override init() {
		super.init()
		acceptedMIMETypes = ["application/json", "text/javascript"]
	}
}
