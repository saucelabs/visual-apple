#import <Foundation/Foundation.h>
#if SAUCEVISUAL_SOURCE_PACKAGE
@import SauceVisual;
#else
#import <SauceVisual/SauceVisual-Swift.h>
#endif

// Takes one snapshot. Credentials come from SAUCE_USERNAME and SAUCE_ACCESS_KEY,
// and the SDK creates and finishes the build for you. Completion runs on the main thread.
void RunObjectiveCExample(SLVBuildOptions *options, void (^completion)(SLVSnapshot * _Nullable, NSError * _Nullable)) {
    [SLVClient clientWithOptions:options completion:^(SLVClient *client, NSError *error) {
        if (client == nil) {
            completion(nil, error);
            return;
        }
        [client sauceVisualCheckWithName:@"Home screen" completion:^(SLVSnapshot *snapshot, NSError *failure) {
            if (failure == nil) {
                NSLog(@"Sauce Visual build: %@", snapshot.buildId);
            }
            completion(snapshot, failure);
        }];
    }];
}
