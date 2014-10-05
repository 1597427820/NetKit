//
//  XMLElement.swift
//  NetKit
//
//  Created by Mike Godenzi on 28.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public class XMLElement {

	public final weak var parent : XMLElement?
	public final let name : String
	public var text : String? { return nil }
	public var attributes : [String:String]? { return nil }
	public var children : [XMLElement]? { return nil }

	public required init(name : String) {
		self.name = name
	}

	private final class func XMLElementWithElement(element : XMLElement) -> XMLElement {
		var result : XMLElement?
		var hasText = element.text != nil && countElements(element.text!) > 0
		var hasChildren = element.children != nil && element.children!.count > 0
		var hasAttributes = element.attributes != nil && element.attributes!.count > 0
		switch (hasText, hasChildren, hasAttributes) {
		case (true, false, false):
			result = XMLLeaf(name: element.name, text: element.text!)
		case (false, true, false):
			result = XMLList(name: element.name, children: element.children!)
		case (false, false, true):
			result = XMLEmpty(name: element.name, attributes: element.attributes!)
		default:
			result = element
		}
		return result!
	}
}

extension XMLElement {

	public final func elementAtPath(path : String) -> XMLElement? {
		var result : XMLElement? = nil
		let components = path.componentsSeparatedByString(".")
		let count = components.count
		var current : Int = 0
		var first = components[current]
		if countElements(first) == 0 || first == self.name {
			current++
		}
		if current < count {
			var match : XMLElement? = self
			do {
				if let _children = match?.children {
					match = nil
					for element in _children {
						if element.name == components[current] {
							match = element
							break
						}
					}
				}
			} while (match != nil && ++current < count)
			result = match
		}

		return result
	}

	public final func elementsAtPath(path : String) -> [XMLElement] {
		var result = [XMLElement]()
		let components = path.componentsSeparatedByString(".")
		let count = components.count
		var current : Int = 0
		var first = components[current]
		if countElements(first) == 0 || first == self.name {
			current++
		}
		if current < count {
			var matches = [self]
			do {
				var tmp = [XMLElement]()
				for element in matches {
					if let children = element.children {
						tmp += children.filter { $0.name == components[current] }
					}
				}
				matches = tmp
			} while (matches.count > 0 && ++current < count)
			result += matches
		}
		return result
	}

	public final func XMLElementWithContentsOfFile(file : String) -> XMLElement? {
		var result : XMLElement?
		var error : NSError?
		var data = NSData(contentsOfFile: file)
		if let _data = data {
			XMLParser.parse(_data, error: &error)
		}
		return result
	}

	public subscript(index : Int) -> XMLElement? {
		get {
			var result : XMLElement? = nil
			if let _children = self.children {
				result = _children[index]
			}
			return result
		}
	}

	public subscript(key : String) -> XMLElement? {
		get {
			return self.elementAtPath(key)
		}
	}
}

extension XMLElement {

	public final class func XMLElementWithContentsOfFile(path : String) -> XMLElement? {
		var result : XMLElement?
		let data = NSData(contentsOfFile: path)
		var error : NSError?
		if let _data = data {
			result = XMLParser.parse(_data, error: &error)
		}
		return result
	}

	public final class func XMLElementWithData(data : NSData, inout error : NSError?) -> XMLElement? {
		return XMLParser.parse(data, error: &error)
	}
}

extension XMLElement : Printable {

	public var description : String {
		get {
			var attributes = self.attributes?.description ?? ""
			var text = self.text ?? ""
			var children = self.children?.description ?? ""
			return "<\(name) \(attributes)>\(text)</\(name)>\n\(children)"
		}
	}
}

private final class XMLFull : XMLElement {

	private var _text : String?
	private override var text : String? {
		get {
			return _text;
		}
		set {
			_text = newValue
		}
	}

	private var _attributes : [String:String]?
	private override var attributes : [String:String]? {
		get {
			return _attributes
		}
		set {
			_attributes = newValue
		}
	}

	private var _children : [XMLElement]? = [XMLElement]()
	private override var children : [XMLElement]? {
		get {
			return _children
		}
		set {
			_children = newValue
		}
	}

	private convenience init(name : String, text : String, attributes : [String:String], children : [XMLElement]) {
		self.init(name: name)
		self._text = text
		self._attributes = attributes
		self._children = children
	}

	private func addChild(child : XMLElement) {
		_children?.append(child)
	}
}

private final class XMLLeaf : XMLElement {

	private var _text : String = ""
	private override var text : String? {
		return _text;
	}

	private convenience init(name : String, text : String) {
		self.init(name: name)
		self._text = text
	}
}

private final class XMLEmpty : XMLElement {

	private var _attributes = [String:String]()
	private override var attributes : [String:String] {
		return _attributes
	}

	private convenience init(name: String, attributes : [String:String]) {
		self.init(name: name)
		self._attributes = attributes
	}
}

private final class XMLList : XMLElement {

	private var _children = [XMLElement]()
	private override var children : [XMLElement] {
		return _children
	}

	private convenience init(name: String, children : [XMLElement]) {
		self.init(name: name)
		self._children = children
	}

	private func addChild(child : XMLElement) {
		_children.append(child)
	}
}

public final class XMLParser : NSObject {

	private var root : XMLElement?
	private var current : XMLElement?
	private var parents = [XMLElement]()
	private lazy var parser : NKXMLParser = NKXMLParser(delegate: self)!

	public var error : NSError? {
		var result : NSError? = self.parser.error
		return result
	}

	public override init() {
		super.init()
		self.parser.delegate = self
	}

	public func parse(data : NSData) {
		self.parser.parse(data)
	}

	public func end() -> XMLElement? {
		self.parser.end()
		return self.root
	}

	public class func parse(data : NSData, inout error : NSError?) -> XMLElement? {
		let parser = XMLParser()
		parser.parse(data)
		var result = parser.end()
		error = parser.error
		return result
	}
}

extension XMLParser : NKXMLParserDelegate {

	public func parser(parser: NKXMLParser!, didStartElement name: String!, withAttributes attributes: [NSObject : AnyObject]!) {
		let current = XMLFull(name: name)
		current.attributes = attributes as? [String:String]
		if let _root = self.root {
			if let _current = self.current {
				self.parents.append(_current)
			}
			current.parent = self.current
			self.current = current
		} else {
			self.root = current
			self.current = current
		}
	}

	public func parser(parser: NKXMLParser!, didEndElement name: String!, withText text: String!) {
		if let _current = self.current as? XMLFull {
			_current.text = text
			self.current = XMLElement.XMLElementWithElement(_current)
			if let _parent = _current.parent as? XMLFull {
				_parent._children?.append(self.current!)
				self.current!.parent = _parent
			}
		}
		self.current = self.current?.parent
		if self.parents.count > 0 && self.current != nil {
			self.parents.removeLast()
		}
	}
}
