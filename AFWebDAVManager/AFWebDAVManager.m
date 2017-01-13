// AFWebDAVManager.m
//
// Copyright (c) 2014 AFNetworking (http://afnetworking.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFWebDAVManager.h"
#import "ONOXMLDocument.h"

static NSString * const AFWebDAVXMLDeclarationString = @"<?xml version=\"1.0\" encoding=\"utf-8\"?>";

static NSString * AFWebDAVStringForDepth(AFWebDAVDepth depth) {
    switch (depth) {
        case AFWebDAVZeroDepth:
            return @"0";
        case AFWebDAVOneDepth:
            return @"1";
        case AFWebDAVInfinityDepth:
        default:
            return @"infinity";
    }
}

static NSString * AFWebDAVStringForLockScope(AFWebDAVLockScope scope) {
    switch (scope) {
        case AFWebDAVLockScopeShared:
            return @"shared";
        case AFWebDAVLockScopeExclusive:
        default:
            return @"exclusive";
    }
}

static NSString * AFWebDAVStringForLockType(AFWebDAVLockType type) {
    switch (type) {
        case AFWebDAVLockTypeWrite:
        default:
            return @"write";
    }
}

#pragma mark -

@interface AFWebDAVMultiStatusResponse ()
- (instancetype)initWithResponseElement:(ONOXMLElement *)element;
@end

#pragma mark -

@implementation AFWebDAVManager

- (instancetype)initWithBaseURL:(NSURL *)url {
    self = [super initWithBaseURL:url];
    if (!self) {
        return nil;
    }

    self.namespacesKeyedByAbbreviation = @{@"D": @"DAV:"};

    self.requestSerializer = [AFWebDAVRequestSerializer serializer];
    self.responseSerializer = [AFCompoundResponseSerializer compoundSerializerWithResponseSerializers:@[[AFWebDAVMultiStatusResponseSerializer serializer], [AFHTTPResponseSerializer serializer]]];

    self.operationQueue.maxConcurrentOperationCount = 1;

    return self;
}

#pragma mark -

- (void)contentsOfDirectoryAtURLString:(NSString *)URLString
                             recursive:(BOOL)recursive
                     completionHandler:(void (^)(NSArray *items, NSError *error))completionHandler
{
    [self PROPFIND:URLString propertyNames:nil depth:(recursive ? AFWebDAVInfinityDepth : AFWebDAVOneDepth) success:^(__unused AFHTTPRequestOperation *operation, id responseObject) {
        if (completionHandler) {
            completionHandler(responseObject, nil);
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        if (completionHandler) {
            completionHandler(nil, error);
        }
    }];
}

- (void)createDirectoryAtURLString:(NSString *)URLString
       withIntermediateDirectories:(BOOL)createIntermediateDirectories
                 completionHandler:(void (^)(NSURL *directoryURL, NSError *error))completionHandler
{
    __weak __typeof(self) weakself = self;
    [self MKCOL:URLString success:^(__unused AFHTTPRequestOperation *operation, NSURLResponse *response) {
        if (completionHandler) {
            if ([response respondsToSelector:@selector(URL)]) {
                completionHandler([response URL], nil);
            } else {
                completionHandler(nil, nil);
            }
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        __strong __typeof(weakself) strongSelf = weakself;
        if ([operation.response statusCode] == 409 && createIntermediateDirectories) {
            NSArray *pathComponents = [[operation.request URL] pathComponents];
            if ([pathComponents count] > 1) {
                [pathComponents enumerateObjectsUsingBlock:^(NSString *component, NSUInteger idx, __unused BOOL *stop) {
                    NSString *intermediateURLString = [[[pathComponents subarrayWithRange:NSMakeRange(0, idx)] arrayByAddingObject:component] componentsJoinedByString:@"/"];
                    [strongSelf MKCOL:intermediateURLString success:^(__unused AFHTTPRequestOperation *MKCOLOperation, __unused NSURLResponse *MKCOLResponse) {

                    } failure:^(__unused AFHTTPRequestOperation *MKCOLOperation, NSError *MKCOLError) {
                        if (completionHandler) {
                            completionHandler(nil, MKCOLError);
                        }
                    }];
                }];
            }
        } else {
            if (completionHandler) {
                completionHandler(nil, error);
            }
        }
    }];
}

- (void)createFileAtURLString:(NSString *)URLString
  withIntermediateDirectories:(BOOL)createIntermediateDirectories
                     contents:(NSData *)contents
            completionHandler:(void (^)(NSURL *fileURL, NSError *error))completionHandler
{
    __weak __typeof(self) weakself = self;
    [self PUT:URLString data:contents success:^(AFHTTPRequestOperation *operation, __unused id responseObject) {
        if (completionHandler) {
            completionHandler([operation.response URL], nil);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        __strong __typeof(weakself) strongSelf = weakself;
        if ([operation.response statusCode] == 409 && createIntermediateDirectories) {
            NSArray *pathComponents = [[operation.request URL] pathComponents];
            if ([pathComponents count] > 1) {
                [strongSelf createDirectoryAtURLString:[[pathComponents subarrayWithRange:NSMakeRange(0, [pathComponents count] - 1)] componentsJoinedByString:@"/"] withIntermediateDirectories:YES completionHandler:^(__unused NSURL *directoryURL, NSError *MKCOLError) {
                    if (MKCOLError) {
                        if (completionHandler) {
                            completionHandler(nil, MKCOLError);
                        }
                    } else {
                        [strongSelf createFileAtURLString:URLString withIntermediateDirectories:NO contents:contents completionHandler:completionHandler];
                    }
                }];
            }
        } else {
            if (completionHandler) {
                completionHandler(nil, error);
            }
        }
    }];
}

- (void)removeFileAtURLString:(NSString *)URLString
            completionHandler:(void (^)(NSURL *fileURL, NSError *error))completionHandler
{
    [self DELETE:URLString parameters:nil success:^(AFHTTPRequestOperation *operation, __unused id responseObject) {
        if (completionHandler) {
            completionHandler([operation.response URL], nil);
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        if (completionHandler) {
            completionHandler(nil, error);
        }
    }];
}

- (void)moveItemAtURLString:(NSString *)originURLString
                toURLString:(NSString *)destinationURLString
                  overwrite:(BOOL)overwrite
          completionHandler:(void (^)(NSURL *fileURL, NSError *error))completionHandler
{
    [self MOVE:originURLString destination:destinationURLString overwrite:overwrite conditions:nil success:^(AFHTTPRequestOperation *operation, __unused id responseObject) {
        if (completionHandler) {
            completionHandler([operation.response URL], nil);
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        if (completionHandler) {
            completionHandler(nil, error);
        }
    }];
}

- (void)copyItemAtURLString:(NSString *)originURLString
                toURLString:(NSString *)destinationURLString
                  overwrite:(BOOL)overwrite
          completionHandler:(void (^)(NSURL *fileURL, NSError *error))completionHandler
{
    [self COPY:originURLString destination:destinationURLString overwrite:overwrite conditions:nil success:^(AFHTTPRequestOperation *operation, __unused id responseObject) {
        if (completionHandler) {
            completionHandler([operation.response URL], nil);
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        if (completionHandler) {
            completionHandler(nil, error);
        }
    }];
}

- (void)contentsOfFileAtURLString:(NSString *)URLString
                completionHandler:(void (^)(NSData *contents, NSError *error))completionHandler
{
    [self GET:URLString parameters:nil success:^(AFHTTPRequestOperation *operation, __unused id responseObject) {
        if (completionHandler) {
            completionHandler(operation.responseData, nil);
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        if (completionHandler) {
            completionHandler(nil, error);
        }
    }];
}

#pragma mark -

- (AFHTTPRequestOperation *)PUT:(NSString *)URLString
                           data:(NSData *)data
                        success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                        failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"PUT" URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString] parameters:nil error:nil];
    request.HTTPBody = data;

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

- (AFHTTPRequestOperation *)PUT:(NSString *)URLString
                           file:(NSURL *)fileURL
                        success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                        failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSParameterAssert(fileURL && [fileURL isFileURL]);

    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"PUT" URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString] parameters:nil error:nil];
    request.HTTPBodyStream = [NSInputStream inputStreamWithURL:fileURL];

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

#pragma mark -


- (AFHTTPRequestOperation *)PROPFIND:(NSString *)URLString
                       propertyNames:(NSArray *)propertyNames
                               depth:(AFWebDAVDepth)depth
                             success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                             failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableString *mutableXMLString = [NSMutableString stringWithString:AFWebDAVXMLDeclarationString];
    {
        [mutableXMLString appendString:@"<D:propfind"];
        [self.namespacesKeyedByAbbreviation enumerateKeysAndObjectsUsingBlock:^(NSString *abbreviation, NSString *namespace, __unused BOOL *stop) {
            [mutableXMLString appendFormat:@" xmlns:%@=\"%@\"", abbreviation, namespace];
        }];
        [mutableXMLString appendString:@">"];

        if (propertyNames) {
            [propertyNames enumerateObjectsUsingBlock:^(NSString *property, __unused NSUInteger idx, __unused BOOL *stop) {
                [mutableXMLString appendFormat:@"<%@/>", property];
            }];
        } else {
            [mutableXMLString appendString:@"<D:allprop/>"];
        }

        [mutableXMLString appendString:@"</D:propfind>"];
    }

    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"PROPFIND" URLString:[[self.baseURL URLByAppendingPathComponent:URLString] absoluteString] parameters:nil error:nil];
	[request setValue:AFWebDAVStringForDepth(depth) forHTTPHeaderField:@"Depth"];
    [request setValue:@"application/xml" forHTTPHeaderField:@"Content-Type:"];
    [request setHTTPBody:[mutableXMLString dataUsingEncoding:NSUTF8StringEncoding]];

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

- (AFHTTPRequestOperation *)PROPPATCH:(NSString *)URLString
                                  set:(NSDictionary *)propertiesToSet
                               remove:(NSArray *)propertiesToRemove
                              success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                              failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableString *mutableXMLString = [NSMutableString stringWithString:AFWebDAVXMLDeclarationString];
    {
        [mutableXMLString appendString:@"<D:propertyupdate"];
        [self.namespacesKeyedByAbbreviation enumerateKeysAndObjectsUsingBlock:^(NSString *abbreviation, NSString *namespace, __unused BOOL *stop) {
            [mutableXMLString appendFormat:@" xmlns:%@=\"%@\"", abbreviation, namespace];
        }];
        [mutableXMLString appendString:@">"];

        if (propertiesToSet) {
            [mutableXMLString appendString:@"<D:set>"];
            {
                [propertiesToSet enumerateKeysAndObjectsUsingBlock:^(NSString *property, id value, __unused BOOL *stop) {
                    [mutableXMLString appendFormat:@"<%@>", property];
                    [mutableXMLString appendString:[value description]];
                    [mutableXMLString appendFormat:@"</%@>", property];
                }];
            }
            [mutableXMLString appendString:@"</D:set>"];
        }

        if (propertiesToRemove) {
            [mutableXMLString appendString:@"<D:remove>"];
            {
                [propertiesToRemove enumerateObjectsUsingBlock:^(NSString *property, __unused NSUInteger idx, __unused BOOL *stop) {
                    [mutableXMLString appendFormat:@"<D:prop><%@/></D:prop>", property];
                }];
            }
            [mutableXMLString appendString:@"</D:remove>"];
        }

        [mutableXMLString appendString:@"</D:propertyupdate>"];
    }

    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"PROPPATCH" URLString:[[self.baseURL URLByAppendingPathComponent:URLString] absoluteString] parameters:nil error:nil];
    [request setValue:@"application/xml" forHTTPHeaderField:@"Content-Type:"];
    [request setHTTPBody:[mutableXMLString dataUsingEncoding:NSUTF8StringEncoding]];

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];
    
    return operation;
}

- (AFHTTPRequestOperation *)MKCOL:(NSString *)URLString
                          success:(void (^)(AFHTTPRequestOperation *operation, NSURLResponse *response))success
                          failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"MKCOL" URLString:[[self.baseURL URLByAppendingPathComponent:URLString] absoluteString] parameters:nil error:nil];

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

- (AFHTTPRequestOperation *)COPY:(NSString *)sourceURLString
                     destination:(NSString *)destinationURLString
                       overwrite:(BOOL)overwrite
                      conditions:(NSString *)IfHeaderFieldValue
                         success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                         failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"COPY" URLString:[[self.baseURL URLByAppendingPathComponent:sourceURLString] absoluteString] parameters:nil error:nil];
    [request setValue:[[self.baseURL URLByAppendingPathComponent:destinationURLString] absoluteString] forHTTPHeaderField:@"Destination"];
    [request setValue:(overwrite ? @"T" : @"F") forHTTPHeaderField:@"Overwrite"];
    if (IfHeaderFieldValue) {
        [request setValue:IfHeaderFieldValue forHTTPHeaderField:@"If"];
    }

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

- (AFHTTPRequestOperation *)MOVE:(NSString *)sourceURLString
                     destination:(NSString *)destinationURLString
                       overwrite:(BOOL)overwrite
                      conditions:(NSString *)IfHeaderFieldValue
                         success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                         failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"MOVE" URLString:[[self.baseURL URLByAppendingPathComponent:sourceURLString] absoluteString] parameters:nil error:nil];
    [request setValue:[[self.baseURL URLByAppendingPathComponent:destinationURLString] absoluteString] forHTTPHeaderField:@"Destination"];
    [request setValue:(overwrite ? @"T" : @"F") forHTTPHeaderField:@"Overwrite"];
    if (IfHeaderFieldValue) {
        [request setValue:IfHeaderFieldValue forHTTPHeaderField:@"If"];
    }

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

- (AFHTTPRequestOperation *)LOCK:(NSString *)URLString
                         timeout:(NSTimeInterval)timeoutInterval
                           depth:(AFWebDAVDepth)depth
                           scope:(AFWebDAVLockScope)scope
                            type:(AFWebDAVLockType)type
                           owner:(NSURL *)ownerURL
                         success:(void (^)(AFHTTPRequestOperation *operation, NSString *lockToken))success
                         failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableString *mutableXMLString = [NSMutableString stringWithString:AFWebDAVXMLDeclarationString];
    {
        [mutableXMLString appendString:@"<D:lockinfo"];
        [self.namespacesKeyedByAbbreviation enumerateKeysAndObjectsUsingBlock:^(NSString *abbreviation, NSString *namespace, __unused BOOL *stop) {
            [mutableXMLString appendFormat:@" xmlns:%@=\"%@\"", abbreviation, namespace];
        }];
        [mutableXMLString appendString:@">"];

        [mutableXMLString appendFormat:@"<D:lockscope><D:%@/></D:lockscope>", AFWebDAVStringForLockScope(scope)];
        [mutableXMLString appendFormat:@"<D:locktype><D:%@/></D:locktype>", AFWebDAVStringForLockType(type)];
        if (ownerURL) {
            [mutableXMLString appendFormat:@"<D:owner><D:href>%@</D:href></D:owner>", [ownerURL absoluteString]];
        }

        [mutableXMLString appendString:@"</D:lockinfo>"];
    }

    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"LOCK" URLString:[[self.baseURL URLByAppendingPathComponent:URLString] absoluteString] parameters:nil error:nil];
    [request setValue:AFWebDAVStringForDepth(depth) forHTTPHeaderField:@"Depth"];
    if (timeoutInterval > 0) {
        [request setValue:[@(timeoutInterval) stringValue] forHTTPHeaderField:@"Timeout"];
    }

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

- (AFHTTPRequestOperation *)UNLOCK:(NSString *)URLString
                             token:(NSString *)lockToken
                           success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                           failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:@"UNLOCK" URLString:[[self.baseURL URLByAppendingPathComponent:URLString] absoluteString] parameters:nil error:nil];
    [request setValue:lockToken forHTTPHeaderField:@"Lock-Token"];

    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];
    [self.operationQueue addOperation:operation];

    return operation;
}

@end

#pragma mark -

@implementation AFWebDAVRequestSerializer

@end

@implementation AFWebDAVSharePointRequestSerializer

#pragma mark - AFURLResponseSerializer

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing *)error
{
    NSMutableURLRequest *mutableRequest = [[super requestBySerializingRequest:request withParameters:parameters error:error] mutableCopy];
    NSString *unescapedURLString = CFBridgingRelease(CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (__bridge CFStringRef)([[request URL] absoluteString]), NULL, kCFStringEncodingASCII));
    mutableRequest.URL = [NSURL URLWithString:unescapedURLString];

    return mutableRequest;
}

@end

#pragma mark -

@implementation AFWebDAVMultiStatusResponseSerializer

- (id)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.acceptableContentTypes = [[NSSet alloc] initWithObjects:@"application/xml", @"text/xml", nil];
    self.acceptableStatusCodes = [NSIndexSet indexSetWithIndex:207];

    return self;
}

#pragma mark - AFURLResponseSerializer

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error
{
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        return nil;
    }

    NSMutableArray *mutableResponses = [NSMutableArray array];

    ONOXMLDocument *XMLDocument = [ONOXMLDocument XMLDocumentWithData:data error:error];
    for (ONOXMLElement *element in [XMLDocument.rootElement childrenWithTag:@"response"]) {
        AFWebDAVMultiStatusResponse *memberResponse = [[AFWebDAVMultiStatusResponse alloc] initWithResponseElement:element];
        if (memberResponse) {
            [mutableResponses addObject:memberResponse];
        }
    }

    return [NSArray arrayWithArray:mutableResponses];
}

@end

#pragma mark -

@interface AFWebDAVMultiStatusResponse ()
@property (readwrite, nonatomic, assign, getter=isCollection) BOOL collection;
@property (readwrite, nonatomic, assign) NSUInteger contentLength;
@property (readwrite, nonatomic, copy) NSDate *creationDate;
@property (readwrite, nonatomic, copy) NSDate *lastModifiedDate;


//! add by OYXJ, used to retrieve some wanted data of XML.
@property (readwrite, nonatomic, strong) ONOXMLElement *element;//strong


/**
 begin --- 实现协议 WebDavResource --- begin
 */

//! The `etag` of the resource at the response URL.
@property(nonatomic, copy, readwrite) NSString *etag;

/**
 服务端资源的唯一id(主键)
 */
@property(nonatomic, copy, readwrite) NSString *name; // 相当于 source id

//@property(nonatomic, copy, readonly) NSString *ctag;

@property(nonatomic, strong, readwrite)NSDictionary<NSString*, NSString*> *customProps;

//private final Resourcetype resourceType; ???
//private final String contentType; ??? TODO::
//private final Long contentLength; ??? TODO::

@property(nonatomic, copy, readwrite) NSString *notedata;
@property(nonatomic, copy, readwrite) NSString *lastModified;
@property(nonatomic, copy, readwrite) NSString *deletedTime;
@property(nonatomic, copy, readwrite) NSString *deletedDataName;
@property(nonatomic, copy, readwrite) NSString *deleted;

/**
 end --- 实现协议 WebDavResource --- end
 */



@end



@implementation AFWebDAVMultiStatusResponse

// by OYXJ
NSString * const getcontentlengthCONST = @"getcontentlength";
NSString * const creationdateCONST = @"creationdate";
NSString * const getlastmodifiedCONST = @"getlastmodified";
NSString * const getetagCONST = @"getetag";//实现协议 WebDavResource

// 实现协议 WebDavResource
NSString * const resourcetypeCONST = @"resourcetype";
NSString * const getcontenttypeCONST = @"getcontenttype";
NSString * const notedataCONST = @"notedata";
NSString * const getDeletedTimeCONST = @"getDeletedTime";
NSString * const getDeletedDataNameCONST = @"getDeletedDataName";
NSString * const getDeletedCONST = @"getDeleted";


#pragma mark - init

- (instancetype)initWithResponseElement:(ONOXMLElement *)element {
    NSParameterAssert(element);
    
    
    /*
     <d:response>
     <d:href>/sync/chatcontacts/f5187830e27a4120bd17107c62011ba5</d:href>
     <d:propstat>
     <d:prop>
     <d:getetag>W/"db3b4d0b9c05509d3967a56b4a0a0353"</d:getetag>
     <x2:chatcontacts-data xmlns:x2="urn:ietf:params:xml:ns:webdav">{"source_id":"f5187830e27a4120bd17107c62011ba5","display_name":"vhs","phone_number":"13716750071#13716750075","is_voip_number":"1","account_phone_number":"13661248236","contact_type":0,"contact_from":0,"device_id":"--866647020047438"}</x2:chatcontacts-data>
     </d:prop>
     <d:status>HTTP/1.1 200 OK</d:status>
     </d:propstat>
     </d:response>
     */
    
    
    /**
     WebDav Response Namespace not always 'D'
     Ref.:  https://github.com/BitSuites/AFWebDAVManager/commit/c25abdb71e07897212b44212e2d854e744a64048
     rocket0423 committed on 10 Jul 2015
     1 parent 45504c7 commit c25abdb71e07897212b44212e2d854e744a64048
     
     NSString *href = [[element firstChildWithTag:@"href" inNamespace:@"D"] stringValue];
     NSInteger status = [[[element firstChildWithTag:@"status" inNamespace:@"D"] numberValue] integerValue];
     */
    NSString *href = [[element firstChildWithTag:@"href"] stringValue];
    NSInteger status = [[[element firstChildWithTag:@"status"] numberValue] integerValue];
    
    if (status == 0) {//[begin] fix bug: ｀status code｀ not found in firstChild element.
        NSString *statusString = [[[element firstChildWithTag:@"propstat"] firstChildWithTag:@"status"] stringValue];
        statusString = [statusString stringByReplacingOccurrencesOfString:@"HTTP/1.1" withString:@""];
        statusString = [statusString stringByTrimmingCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
        statusString = [statusString stringByTrimmingCharactersInSet:[NSCharacterSet letterCharacterSet]];
        statusString = [statusString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (statusString.length > 0) {
            if ([statusString integerValue] > 0) {
                status = [statusString integerValue];
            }
        }
    }//[end] fix bug: ｀status code｀ not found in firstChild element.
    
    
    self = [self initWithURL:[NSURL URLWithString:href] statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
    {//element
        //TODO: A true deep copy  http://stackoverflow.com/questions/647260/deep-copying-an-nsarray
        self.element = element;//strong reference
        {//解析数据---begin//
            NSDictionary *atts = [element attributes];
            if (atts.count > 0) {
                //开源库Ono
                self.customProps = atts;
            }else{
                //自己 解析数据
                ONOXMLElement *propElement = [[element firstChildWithTag:@"propstat"] firstChildWithTag:@"prop"];
                
                
                NSMutableDictionary<NSString*,NSString*> *proDic = [NSMutableDictionary dictionaryWithCapacity:2];
                
                NSArray<ONOXMLElement*> *childrenElements = [propElement children];
                for (int i = 0; i < childrenElements.count; i++) {
                    ONOXMLElement *e = childrenElements[i];
                    NSString *aTag = [e tag];
                    NSString *stringValue = [self valueOfTag: aTag
                                                   inElement: e];
                    if (aTag.length && stringValue.length) {
                        [proDic setObject:stringValue forKey:aTag];
                    }
                }
                
                //DDLogVerbose(@"%@", proDic);
                
                self.customProps = proDic;
            }
        }//解析数据---end//
    }//element
    if (!self) {
        return nil;
    }
    
    ONOXMLElement *propElement = [[element firstChildWithTag:@"propstat"] firstChildWithTag:@"prop"];
    for (ONOXMLElement *resourcetypeElement in [propElement childrenWithTag:@"resourcetype"]) {
        if ([resourcetypeElement childrenWithTag:@"collection"].count > 0) {
            self.collection = YES;
            break;
        }
    }
    
    
    /**
     WebDav Response Namespace not always 'D'
     Ref.:  https://github.com/BitSuites/AFWebDAVManager/commit/c25abdb71e07897212b44212e2d854e744a64048
     rocket0423 committed on 10 Jul 2015
     1 parent 45504c7 commit c25abdb71e07897212b44212e2d854e744a64048
     
     self.contentLength = [[[propElement firstChildWithTag:@"getcontentlength" inNamespace:@"D"] numberValue] unsignedIntegerValue];
     self.creationDate = [[propElement firstChildWithTag:@"creationdate" inNamespace:@"D"] dateValue];
     self.lastModifiedDate = [[propElement firstChildWithTag:@"getlastmodified" inNamespace:@"D"] dateValue];
     */
    
    
    //by OYXJ
    NSString *ns = [propElement namespace];
    NSMutableArray<NSString*> *beginEndTAGs = [NSMutableArray arrayWithCapacity:2];
    NSArray * const tags = @[getcontentlengthCONST,creationdateCONST,getlastmodifiedCONST,getetagCONST];
    [tags enumerateObjectsUsingBlock:^(id  _Nonnull eachTag, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *beginTAG = [NSString stringWithFormat:@"<%@:%@>", ns,eachTag];
        NSString *endTAG  = [NSString stringWithFormat:@"</%@:%@>", ns,eachTag];
        [beginEndTAGs addObject: beginTAG];
        [beginEndTAGs addObject: endTAG];
    }];
    
    
    {//getcontentlength
        self.contentLength = [[[propElement firstChildWithTag:getcontentlengthCONST]
                               numberValue] unsignedIntegerValue];
        if (self.contentLength==0) {//by OYXJ
            NSMutableString *contentLengthSTR = [[[propElement firstChildWithTag:getcontentlengthCONST]
                                                  stringValue] mutableCopy];
            [beginEndTAGs enumerateObjectsUsingBlock:^(id  _Nonnull aTAG, NSUInteger idx, BOOL * _Nonnull stop) {
                [contentLengthSTR replaceOccurrencesOfString:aTAG
                                                  withString:@""
                                                     options:NSLiteralSearch
                                                       range:NSMakeRange(0, contentLengthSTR.length)];
            }];
            
            NSNumber *aContentLength = [propElement.document.numberFormatter numberFromString:contentLengthSTR];
            
            self.contentLength = [aContentLength unsignedIntegerValue];
        }
    }//getcontentlength
    
    {//creationdate
        self.creationDate = [[propElement firstChildWithTag:creationdateCONST] dateValue];
        if (self.creationDate==nil) {//by OYXJ
            NSMutableString *creationDateSTR = [[[propElement firstChildWithTag:creationdateCONST]
                                                 stringValue] mutableCopy];
            [beginEndTAGs enumerateObjectsUsingBlock:^(id  _Nonnull aTAG, NSUInteger idx, BOOL * _Nonnull stop) {
                [creationDateSTR replaceOccurrencesOfString:aTAG
                                                 withString:@""
                                                    options:NSLiteralSearch
                                                      range:NSMakeRange(0, creationDateSTR.length)];
            }];
            
            NSDate *aCreationDate = [propElement.document.dateFormatter dateFromString:creationDateSTR];
            if (aCreationDate==nil) {
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                //[dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];//by OYXJ
                //[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];//by OYXJ
                [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];//by OYXJ
                
                aCreationDate = [dateFormatter dateFromString:creationDateSTR];
            }
            
            self.creationDate = aCreationDate;
        }
    }//creationdate
    
    
    {//getlastmodified
        self.lastModifiedDate = [[propElement firstChildWithTag:getlastmodifiedCONST] dateValue];
        if (self.lastModifiedDate==nil) {//by OYXJ
            NSMutableString *lastModifiedDateSTR = [[[propElement firstChildWithTag:getlastmodifiedCONST]
                                                     stringValue] mutableCopy];
            [beginEndTAGs enumerateObjectsUsingBlock:^(id  _Nonnull aTAG, NSUInteger idx, BOOL * _Nonnull stop) {
                [lastModifiedDateSTR replaceOccurrencesOfString:aTAG
                                                     withString:@""
                                                        options:NSLiteralSearch
                                                          range:NSMakeRange(0, lastModifiedDateSTR.length)];
            }];
            
            NSDate *aLastModifiedDate = [propElement.document.dateFormatter dateFromString:lastModifiedDateSTR];
            if (aLastModifiedDate==nil) {
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                //[dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];//by OYXJ
                //[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];//by OYXJ
                [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];//by OYXJ
                
                aLastModifiedDate = [dateFormatter dateFromString:lastModifiedDateSTR];
            }
            
            self.lastModifiedDate = aLastModifiedDate;
        }
    }//getlastmodified
    
    
    {//getetag
        NSMutableString *aEtagSTR = [[[propElement firstChildWithTag:getetagCONST]
                                      stringValue] mutableCopy];
        [beginEndTAGs enumerateObjectsUsingBlock:^(id  _Nonnull aTAG, NSUInteger idx, BOOL * _Nonnull stop) {
            [aEtagSTR replaceOccurrencesOfString:aTAG
                                      withString:@""
                                         options:NSLiteralSearch
                                           range:NSMakeRange(0, aEtagSTR.length)];
        }];
        
        self.etag = [aEtagSTR copy];
    }//getetag
    
    
    return self;
}


#pragma mark - private

/**
 根据标签名字，获取标签的值
 特别注意，标签的值，是String类型，才使用此方法。
 
 @param aTagNameCONST 标签名字，使用此类中定义的 常量字符串
 
 @return 标签的值
 */
- (NSString *)valueOfTag:(NSString *)aTagNameCONST inElement:(ONOXMLElement *)anElement
{
    if (aTagNameCONST.length <= 0) {
        return nil;
    }
    if (anElement == nil) {
        return nil;
    }
    
    NSString *returnStr = nil;
    @try {
        //Code that can potentially throw an exception
        
        NSMutableString *aTagValueSTR = [[anElement stringValue] mutableCopy];
        
        
        if ([aTagValueSTR rangeOfString:aTagNameCONST].location == NSNotFound) {
            // do nothing here !
        }else{
            
            NSString *ns = [anElement namespace];
            NSMutableArray *beginEndTAGs = [NSMutableArray arrayWithCapacity:1];
            [@[aTagNameCONST] enumerateObjectsUsingBlock:^(id  _Nonnull eachTag, NSUInteger idx, BOOL * _Nonnull stop) {
                NSString *beginTAG = [NSString stringWithFormat:@"<%@:%@>", ns,eachTag];
                NSString *endTAG  = [NSString stringWithFormat:@"</%@:%@>", ns,eachTag];
                [beginEndTAGs addObject: beginTAG];
                [beginEndTAGs addObject: endTAG];
            }];
            
            [beginEndTAGs enumerateObjectsUsingBlock:^(id  _Nonnull aTAG, NSUInteger idx, BOOL * _Nonnull stop) {
                [aTagValueSTR replaceOccurrencesOfString:aTAG
                                              withString:@""
                                                 options:NSLiteralSearch
                                                   range:NSMakeRange(0, aTagValueSTR.length)];
            }];
        }
        
        returnStr = [aTagValueSTR copy];
        
    } @catch (NSException *exception) {
        //Handle an exception thrown in the @try block
        
        NSLog(@"%@", exception);
        
    } @finally {
        //Code that gets executed whether or not an exception is thrown
        
        return returnStr;
    }
    
}


#pragma mark - getters

- (NSString *)etag
{
    return _etag;
}

/**
 服务端资源的唯一id(主键)
 相当于 source id
 */
- (NSString *)name
{
    if (nil==_name) {
        _name = self.URL.absoluteString.lastPathComponent ?: self.URL.absoluteString;
    }
    
    return _name;
}

//- (NSString *)ctag
//{
//    return _ctag;
//}

- (NSDictionary<NSString*,NSString*> *)customProps
{
    return _customProps;
}

//private final Resourcetype resourceType; ???
//private final String contentType; ??? TODO::
//private final Long contentLength; ??? TODO::



- (NSString *)notedata
{
    if (nil==_notedata) {
        
        ONOXMLElement *propElement = [[self.element firstChildWithTag:@"propstat"] firstChildWithTag:@"prop"];
        _notedata = [self valueOfTag: notedataCONST
                           inElement: [propElement firstChildWithTag:notedataCONST]];
    }
    
    return _notedata;
}

- (NSString *)lastModified
{
    if (nil==_lastModified) {
        
        _lastModified = [self.lastModifiedDate description];
    }
    
    return _lastModified;
}

- (NSString *)deletedTime
{
    if (nil==_deletedTime) {
        
        ONOXMLElement *propElement = [[self.element firstChildWithTag:@"propstat"] firstChildWithTag:@"prop"];
        _deletedTime = [self valueOfTag: getDeletedTimeCONST
                              inElement: [propElement firstChildWithTag:getDeletedTimeCONST]];
    }
    
    return _deletedTime;
}

- (NSString *)deletedDataName
{
    if (nil==_deletedDataName) {
        
        ONOXMLElement *propElement = [[self.element firstChildWithTag:@"propstat"] firstChildWithTag:@"prop"];
        _deletedDataName = [self valueOfTag: getDeletedDataNameCONST
                                  inElement: [propElement firstChildWithTag:getDeletedDataNameCONST]];
    }
    
    return _deletedDataName;
}

- (NSString *)deleted
{
    if (nil==_deleted) {
        
        ONOXMLElement *propElement = [[self.element firstChildWithTag:@"propstat"] firstChildWithTag:@"prop"];
        _deleted = [self valueOfTag: getDeletedCONST
                          inElement: [propElement firstChildWithTag:getDeletedCONST]];
    }
    
    return _deleted;
}


@end
