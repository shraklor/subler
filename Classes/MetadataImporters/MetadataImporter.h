//
//  MetadataImporter.h
//  Subler
//
//  Created by Douglas Stebila on 2013-05-30.
//
//

#import <Foundation/Foundation.h>

@class MP42Metadata;

NS_ASSUME_NONNULL_BEGIN

@interface MetadataImporter : NSObject {
@private
    BOOL _isCancelled;
}

typedef enum SBCachePolicy : NSUInteger {
    SBDefaultPolicy = 0,
    SBReturnCacheElseLoad,
    SBReloadIgnoringLocalCacheData,
} SBCachePolicy;

#pragma mark Helper routines
+ (NSDictionary *)parseFilename:(NSString *)filename;
+ (NSString *)urlEncoded:(NSString *)string;
+ (nullable NSData *)downloadDataFromURL:(NSURL *)url withCachePolicy:(SBCachePolicy)policy;

#pragma mark Class methods
+ (NSArray<NSString *> *) movieProviders;
+ (NSArray<NSString *> *) tvProviders;
+ (NSArray<NSString *> *) languagesForProvider:(NSString *)aProvider;
+ (instancetype) importerForProvider:(NSString *)aProviderName;
+ (instancetype) defaultMovieProvider;
+ (instancetype) defaultTVProvider;
+ (NSString *) defaultMovieLanguage;
+ (NSString *) defaultTVLanguage;

+ (NSString *) defaultLanguageForProvider:(NSString *)provider;

#pragma mark Asynchronous searching
- (void) searchTVSeries:(NSString *)aSeries language:(NSString *)aLanguage completionHandler:(void(^)(NSArray<MP42Metadata *> * _Nullable results))handler;
- (void) searchTVSeries:(NSString *)aSeries language:(NSString *)aLanguage seasonNum:(NSString *)aSeasonNum episodeNum:(NSString *)aEpisodeNum completionHandler:(void(^)(NSArray<MP42Metadata *> * _Nullable results))handler;

- (void) searchMovie:(NSString *)aMovieTitle language:(NSString *)aLanguage completionHandler:(void(^)(NSArray<MP42Metadata *> * _Nullable results))handler;

- (void) loadFullMetadata:(MP42Metadata *)aMetadata language:(NSString *)aLanguage completionHandler:(void(^)(MP42Metadata * _Nullable metadata))handler;

- (void) cancel;

#pragma mark Methods to be overridden
- (NSArray<NSString *> *) languages;

- (NSArray<MP42Metadata *> * _Nullable) searchTVSeries:(NSString *)aSeriesName language:(NSString *)aLanguage;
- (NSArray<MP42Metadata *> * _Nullable) searchTVSeries:(NSString *)aSeriesName language:(NSString *)aLanguage seasonNum:(NSString * _Nullable)aSeasonNum episodeNum:(NSString * _Nullable)aEpisodeNum;

- (NSArray<MP42Metadata *> * _Nullable) searchMovie:(NSString *)aMovieTitle language:(NSString *)aLanguage;

- (MP42Metadata * _Nullable) loadTVMetadata:(MP42Metadata *)aMetadata language:(NSString *)aLanguage;
- (MP42Metadata * _Nullable) loadMovieMetadata:(MP42Metadata *)aMetadata language:(NSString *)aLanguage;

@end

NS_ASSUME_NONNULL_END
