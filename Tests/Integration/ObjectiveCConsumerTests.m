#import <XCTest/XCTest.h>
#if SAUCEVISUAL_SOURCE_PACKAGE
@import SauceVisual;
#else
#import <SauceVisual/SauceVisual-Swift.h>
#endif

extern void RunObjectiveCExample(SLVBuildOptions *options, void (^completion)(SLVSnapshot * _Nullable, NSError * _Nullable));

@interface ObjectiveCConsumerTests : XCTestCase
@end

@implementation ObjectiveCConsumerTests

- (void)testObjectiveCExampleReportsConstructorErrorOnMainThread {
    // Fails before any request, so no backend is needed: on missing credentials, or else the bad build ID.
    SLVBuildOptions *options = [[SLVBuildOptions alloc] initWithName:@"Checkout flow" project:nil branch:nil
                                                       defaultBranch:nil customId:nil buildId:@"not-a-uuid"
                                                         finishDelay:nil tags:nil];
    XCTestExpectation *done = [self expectationWithDescription:@"Objective-C example"];
    done.assertForOverFulfill = YES;
    __block BOOL returned = NO;
    RunObjectiveCExample(options, ^(SLVSnapshot *snapshot, NSError *error) {
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertTrue(returned);
        XCTAssertNil(snapshot);
        XCTAssertEqualObjects(error.domain, SLVClient.errorDomain);
        XCTAssertTrue(error.code == SLVErrorCodeInvalidCredentials || error.code == SLVErrorCodeInvalidBuildId,
                      @"Unexpected code %ld", (long)error.code);
        [done fulfill];
    });
    returned = YES;
    [self waitForExpectations:@[done] timeout:10.0];
}

- (void)testRegionLookupUsesStableNSErrorCodes {
    NSError *error = nil;
    XCTAssertEqualObjects(SLVRegion.defaultRegion.name, @"us-west-1");
    XCTAssertEqualObjects([SLVRegion regionNamed:@"eu" error:&error].name, @"eu-central-1");
    XCTAssertEqualObjects([SLVRegion regionNamed:@"asia" error:&error].name, @"asia-south-2");
    XCTAssertEqualObjects(SLVRegion.asiaSouth2.graphqlEndpoint.host, @"api.asia-south-2.saucelabs.com");
    XCTAssertNil(error);
    XCTAssertNil([SLVRegion regionNamed:@"mars" error:&error]);
    XCTAssertEqualObjects(error.domain, SLVClient.errorDomain);
    XCTAssertEqual(error.code, SLVErrorCodeUnknownRegion);
}

- (void)testCheckOptionsDefaultToBalancedWithNothingIgnored {
    SLVCheckOptions *options = [[SLVCheckOptions alloc] init];
    XCTAssertEqual(options.diffingMethod, SLVDiffingMethodBalanced);
    XCTAssertEqual(options.ignoreRegions.count, 0u);
    XCTAssertEqual(options.ignoreElements.count, 0u);
    XCTAssertNil(options.testName);
    XCTAssertNil(options.clipElement);
    XCTAssertFalse(options.captureDom);
    XCTAssertNil(options.baselineOverride);
    XCTAssertNil(options.fullPageScrollElement);
    XCTAssertEqual(options.fullPageScrollLimit, 10);
    XCTAssertEqualWithAccuracy(options.fullPageDelayAfterScroll, 0.5, 0.001);
    SLVBaselineOverride *baseline = [[SLVBaselineOverride alloc] init];
    XCTAssertEqual(baseline.operatingSystem, SLVOperatingSystemNotSet);
    baseline.name = @"Login page";
    baseline.operatingSystem = SLVOperatingSystemIos;
    options.baselineOverride = baseline;
    XCTAssertEqualObjects(options.baselineOverride.name, @"Login page");
    CGRect statusBar = CGRectMake(0, 0, 402, 62);
#if TARGET_OS_OSX
    options.ignoreRegions = @[[NSValue valueWithRect:statusBar]];
#else
    options.ignoreRegions = @[[NSValue valueWithCGRect:statusBar]];
#endif
    options.diffingMethod = SLVDiffingMethodExperimental;
    XCTAssertEqual(options.ignoreRegions.count, 1u);
    XCTAssertEqual(options.diffingMethod, SLVDiffingMethodExperimental);
}

- (void)testBaselineOverrideKeepsFieldsAndNullMatches {
    SLVBaselineOverride *baseline = [[SLVBaselineOverride alloc] init];
    baseline.device = @"iPhone 17";
    baseline.operatingSystem = SLVOperatingSystemIos;
    XCTAssertEqualObjects(baseline.device, @"iPhone 17");
    XCTAssertEqual(baseline.operatingSystem, SLVOperatingSystemIos);
    XCTAssertNil(baseline.name);
    XCTAssertFalse([baseline matchesNullFor:SLVBaselineOverrideFieldName]);

    [baseline matchNullFor:SLVBaselineOverrideFieldSuiteName];
    XCTAssertTrue([baseline matchesNullFor:SLVBaselineOverrideFieldSuiteName]);
}

- (void)testBuildOptionsKeepFinishDelay {
    SLVBuildOptions *plain = [[SLVBuildOptions alloc] initWithName:@"Build" project:nil branch:nil
                                                     defaultBranch:nil customId:nil buildId:nil
                                                       finishDelay:nil tags:nil];
    XCTAssertNil(plain.finishDelay);
    SLVBuildOptions *shared = [[SLVBuildOptions alloc] initWithName:@"Build" project:nil branch:nil defaultBranch:nil
                                                           customId:@"ci-42" buildId:nil finishDelay:@120 tags:nil];
    XCTAssertEqualObjects(shared.finishDelay, @120);
    XCTAssertEqualObjects(shared.customId, @"ci-42");

    // A finish delay needs a custom ID. Fails before any request, so no backend is needed.
    SLVBuildOptions *invalid = [[SLVBuildOptions alloc] initWithName:@"Build" project:nil branch:nil defaultBranch:nil
                                                            customId:nil buildId:nil finishDelay:@120 tags:nil];
    XCTestExpectation *done = [self expectationWithDescription:@"Client creation"];
    [SLVClient clientWithUsername:@"user" accessKey:@"key" region:SLVRegion.staging options:invalid
                       completion:^(SLVClient *client, NSError *error) {
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertNil(client);
        XCTAssertEqualObjects(error.domain, SLVClient.errorDomain);
        XCTAssertEqual(error.code, SLVErrorCodeInvalidFinishDelay);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:10.0];
}

- (void)testBuildOptionsKeepTags {
    SLVBuildOptions *options = [[SLVBuildOptions alloc] initWithName:@"Build" project:nil branch:nil defaultBranch:nil
                                                             customId:nil buildId:nil finishDelay:nil
                                                                 tags:@[@"smoke", @"nightly"]];
    XCTAssertEqualObjects(options.tags, (@[@"smoke", @"nightly"]));
    XCTAssertNil(options.finishDelay);
    SLVBuildOptions *plain = [[SLVBuildOptions alloc] initWithName:@"Build" project:nil branch:nil
                                                     defaultBranch:nil customId:nil buildId:nil
                                                       finishDelay:nil tags:nil];
    XCTAssertNil(plain.tags);
}

@end
