//
//  NKXMLParser.h
//  NetKit
//
//  Created by Mike Godenzi on 29.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

@import Foundation;

@class NKXMLParser;

@protocol NKXMLParserDelegate <NSObject>
- (void)parser:(NKXMLParser *)parser didStartElement:(NSString *)name withAttributes:(NSDictionary *)attributes;
- (void)parser:(NKXMLParser *)parser didEndElement:(NSString *)name withText:(NSString *)text;
@end

@interface NKXMLParser : NSObject

@property (nonatomic, strong) NSError * error;
@property (nonatomic, weak) id<NKXMLParserDelegate> delegate;

- (instancetype)initWithDelegate:(id<NKXMLParserDelegate>)delegate;
- (void)parse:(NSData *)data;
- (void)end;

@end
