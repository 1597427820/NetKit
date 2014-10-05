//
//  NKXMLParser.m
//  NetKit
//
//  Created by Mike Godenzi on 29.09.14.
//  Copyright (c) 2014 Mike Godenzi. All rights reserved.
//

#import "NKXMLParser.h"
#import <libxml/tree.h>

static NSString * const NKPathSeparator = @".";
static NSString * const NKXMLExtension = @".xml";

static xmlSAXHandler SAXHandlerStruct;

@implementation NKXMLParser {
@package
	xmlParserCtxtPtr _context;
	NSMutableData * _chars;
	NSMutableSet * _nameSet;
	NSString * _currentName;
}

- (instancetype)init {
	return [self initWithDelegate:nil];
}

- (instancetype)initWithDelegate:(id<NKXMLParserDelegate>)delegate {
	self = [super init];
	if (self) {
		_delegate = delegate;
		_context = xmlCreatePushParserCtxt(&SAXHandlerStruct, (__bridge void *)(self), NULL, 0, NULL);
		_chars = [[NSMutableData alloc] init];
		_nameSet = [[NSMutableSet alloc] init];
	}
	return self;
}

- (void)dealloc {
	xmlFreeParserCtxt(_context);
}

#pragma mark - Public Methods

- (void)parse:(NSData *)data {
	@autoreleasepool {
		xmlParseChunk(_context, (const char *)[data bytes], (int)[data length], 0);
	}
}

- (void)end {
	xmlParseChunk(_context, NULL, 0, 1);
}

@end

#pragma mark - LibXML SAX Callbacks

static void SAXStartElement(void * ctx, const xmlChar * localname, const xmlChar * prefix, const xmlChar * URI, int nb_namespaces, const xmlChar ** namespaces, int nb_attributes, int nb_defaulted, const xmlChar ** attributes) {
	NKXMLParser * parser = (__bridge NKXMLParser *)ctx;
	NSString * name = @((const char *)localname);
	NSString * usedName = [parser->_nameSet member:name];
	if (usedName) {
		name = usedName;
	} else {
		[parser->_nameSet addObject:name];
	}
	parser->_currentName = name;
	NSDictionary * attributesDict = nil;
	NSUInteger count = (NSUInteger)nb_attributes;
	if (count) {
		NSMutableDictionary * mutableAttributes = [[NSMutableDictionary alloc] initWithCapacity:count];
		for (NSUInteger i = 0; i < count; i++, attributes += 5) {
			NSString * key = [[NSString alloc] initWithCString:(const char *)attributes[0] encoding:NSUTF8StringEncoding];
			NSString * val = [[NSString alloc] initWithBytes:(const void *)attributes[3] length:(attributes[4] - attributes[3]) encoding:NSUTF8StringEncoding];
			[mutableAttributes setValue:[val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:key];
		}
		attributesDict = [mutableAttributes copy];
	}
	[parser.delegate parser:parser didStartElement:name withAttributes:attributesDict];
}

static void	SAXEndElement(void * ctx, const xmlChar * localname, const xmlChar * prefix, const xmlChar * URI) {
	NKXMLParser * parser = (__bridge NKXMLParser *)ctx;
	NSString * text = nil;
	NSData * data = parser->_chars;
	if ([data length]) {
		NSString * tmp = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
		text = [tmp stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	[parser->_chars setLength:0];
	[parser.delegate parser:parser didEndElement:parser->_currentName withText:text];
	parser->_currentName = nil;
}

static void	SAXCharactersFound(void * ctx, const xmlChar * ch, int len) {
	NKXMLParser * parser = (__bridge NKXMLParser *)ctx;
	[parser->_chars appendBytes:(const void *)ch length:(NSUInteger)len];
}

static void SAXErrorEncountered(void * ctx, const char * msg, ...) {
	NKXMLParser * parser = (__bridge NKXMLParser *)ctx;
	va_list arguments;
	va_start(arguments, msg);
	NSString * message = [[NSString alloc] initWithFormat:@(msg) arguments:arguments];
	va_end(arguments);
	NSString * finalMessage = [NSString stringWithFormat:@"%@ error: %@", NSStringFromClass([parser class]), message];
	NSDictionary * userInfo = @{NSLocalizedDescriptionKey: finalMessage};
	NSError * error = [NSError errorWithDomain:NSStringFromClass([parser class]) code:666 userInfo:userInfo];
	parser.error = error;
}

// The handler struct has positions for a large number of callback functions. If NULL is supplied at a given position,
// that callback functionality won't be used. Refer to libxml documentation at http://www.xmlsoft.org for more information
// about the SAX callbacks.
static xmlSAXHandler SAXHandlerStruct = {
	NULL,                       /* internalSubset */
	NULL,                       /* isStandalone   */
	NULL,                       /* hasInternalSubset */
	NULL,                       /* hasExternalSubset */
	NULL,                       /* resolveEntity */
	NULL,                       /* getEntity */
	NULL,                       /* entityDecl */
	NULL,                       /* notationDecl */
	NULL,                       /* attributeDecl */
	NULL,                       /* elementDecl */
	NULL,                       /* unparsedEntityDecl */
	NULL,                       /* setDocumentLocator */
	NULL,                       /* startDocument */
	NULL,                       /* endDocument */
	NULL,                       /* startElement*/
	NULL,                       /* endElement */
	NULL,                       /* reference */
	SAXCharactersFound,         /* characters */
	NULL,                       /* ignorableWhitespace */
	NULL,                       /* processingInstruction */
	NULL,                       /* comment */
	NULL,                       /* warning */
	SAXErrorEncountered,        /* error */
	NULL,                       /* fatalError //: unused error() get all the errors */
	NULL,                       /* getParameterEntity */
	NULL,                       /* cdataBlock */
	NULL,                       /* externalSubset */
	XML_SAX2_MAGIC,             //
	NULL,
	SAXStartElement,            /* startElementNs */
	SAXEndElement,              /* endElementNs */
	NULL,                       /* serror */
};
