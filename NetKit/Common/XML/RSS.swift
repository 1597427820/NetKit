//
//  RSS.swift
//  NetKit
//
//  Created by Mike Godenzi on 01.11.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

import Foundation

public struct RSSFeed<T : RSSItem> {

	public let title : String
	public let link : String
	public let decription : String
	public let language : String?
	public let pubDate : String?
	public let lastBuildDate : String?
	public let docs : String?
	public let copyright : String?
	public let editor : String?
	public let webmaster : String?
	public let items : [T]

	public init?(xml : XMLElement) {
		if let channel = xml.elementAtPath("channel") {
			switch (channel["title"]?.text, channel["link"]?.text, channel["description"]?.text) {
			case let (.Some(title), .Some(link), .Some(description)):
				self.title = title
				self.link = link
				self.decription = description
				language = channel["language"]?.text
				pubDate = channel["pubDate"]?.text
				lastBuildDate = channel["lastBuildDate"]?.text
				docs = channel["docs"]?.text
				copyright = channel["copyright"]?.text
				editor = channel["editor"]?.text
				webmaster = channel["webmaster"]?.text
				let xmlItems = channel.elementsAtPath("items");
				if xmlItems.count > 0 {
					var items = [T]()
					items.reserveCapacity(xmlItems.count)
					for xmlItem in xmlItems {
						if let item = T(xml: xmlItem) {
							items.append(item)
						}
					}
					self.items = items;
				} else {
					items = [T]()
				}
			default:
				return nil
			}
		} else {
			return nil
		}
	}
}

public class RSSItem {

	public let title : String
	public let description : String
	public let link : String?
	public let pubDate : String?
	public let category : String?
	public let guid : String?
	public let comments : String?
	public let author : String?

	public init?(xml : XMLElement) {
		title = xml["title"]?.text ?? ""
		description = xml["description"]?.text ?? ""
		if !title.isEmpty && !description.isEmpty {
			link = xml["link"]?.text
			pubDate = xml["pubDate"]?.text
			category = xml["category"]?.text
			guid = xml["guid"]?.text
			comments = xml["comments"]?.text
			author = xml["author"]?.text
		} else {
			return nil;
		}
	}
}
