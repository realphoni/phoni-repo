#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// iOS 12's SpringBoard hardware press types (distinct from public remote keys).
static const NSInteger DSHome = 101;
static const NSInteger DSVolumeDown = 103;
static const NSInteger DSLock = 104;
static char DSScreenshotMarker;
static char DSConfigurePendingMarker;

@interface SBClickGestureRecognizer : UIGestureRecognizer
- (void)addShortcutWithPressTypes:(NSArray<NSNumber *> *)pressTypes;
@end
@interface SBLockHardwareButton : NSObject @end
@interface SBVolumeHardwareButton : NSObject @end
@interface SBCombinationHardwareButton : NSObject
@property (nonatomic, retain) SBClickGestureRecognizer *screenshotGestureRecognizer;
@end

static BOOL DSIsScreenshot(id object) {
    return object && [objc_getAssociatedObject(object, &DSScreenshotMarker) boolValue];
}

static id DSObjectField(id object, const char *name) {
    Ivar field = object ? class_getInstanceVariable([object class], name) : NULL;
    if (!field || ivar_getTypeEncoding(field)[0] != '@') return nil;
    return object_getIvar(object, field);
}

static NSArray<NSNumber *> *DSIncludeVolumeDown(NSArray<NSNumber *> *pressTypes) {
    // Leave unrelated configurations alone, including any empty setup stage.
    if (![pressTypes isKindOfClass:[NSArray class]] || ![pressTypes containsObject:@(DSLock)]) return pressTypes;
    NSMutableArray *result = [pressTypes mutableCopy];
    if (![result containsObject:@(DSVolumeDown)]) [result addObject:@(DSVolumeDown)];
    return result;
}

static void DSConfigure(SBClickGestureRecognizer *recognizer) {
    Class clickClass = NSClassFromString(@"SBClickGestureRecognizer");
    if (!clickClass || ![recognizer isKindOfClass:clickClass] ||
        ![recognizer respondsToSelector:@selector(addShortcutWithPressTypes:)]) return;
    if (DSIsScreenshot(recognizer)) return;
    NSArray *allowed = recognizer.allowedPressTypes;
    if (![allowed containsObject:@(DSLock)]) return;
    // Alternative subsets let either two-button chord satisfy the recognizer.
    // Expanding allowedPressTypes alone would incorrectly require three buttons.
    NSArray *newChord = @[@(DSLock), @(DSVolumeDown)];
    NSArray *homeChord = @[@(DSLock), @(DSHome)];
    if ([allowed containsObject:@(DSHome)]) [recognizer addShortcutWithPressTypes:homeChord];
    [recognizer addShortcutWithPressTypes:newChord];
    objc_setAssociatedObject(recognizer, &DSScreenshotMarker, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray *expanded = DSIncludeVolumeDown(allowed);
    if (![expanded isEqualToArray:allowed]) recognizer.allowedPressTypes = expanded;
}

static void DSRegister(id recognizer) {
    if (!recognizer || ![recognizer isKindOfClass:NSClassFromString(@"SBClickGestureRecognizer")]) return;
    // The same recognizer is passed to both hardware-button controllers.
    // Configure after setup so native shortcuts and timing are already in place.
    if ([objc_getAssociatedObject(recognizer, &DSConfigurePendingMarker) boolValue]) return;
    objc_setAssociatedObject(recognizer, &DSConfigurePendingMarker, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{ DSConfigure(recognizer); });
}

%group IOS12
%hook SBCombinationHardwareButton
- (void)_configureGestureRecognizers {
    %orig;
    DSConfigure(self.screenshotGestureRecognizer);
}
%end

%hook SBLockHardwareButton
- (id)initWithScreenshotGestureRecognizer:(id)screenshot shutdownGestureRecognizer:(id)shutdown proximitySensorManager:(id)proximity homeHardwareButton:(id)home volumeHardwareButton:(id)volume buttonActions:(id)actions homeButtonType:(long long)type createGestures:(BOOL)create {
    id result = %orig;
    if (result) DSRegister(screenshot);
    return result;
}
- (id)initWithScreenshotGestureRecognizer:(id)screenshot shutdownGestureRecognizer:(id)shutdown proximitySensorManager:(id)proximity homeHardwareButton:(id)home volumeHardwareButton:(id)volume homeButtonType:(long long)type {
    id result = %orig;
    if (result) DSRegister(screenshot);
    return result;
}
%end

%hook SBVolumeHardwareButton
- (id)initWithScreenshotGestureRecognizer:(id)screenshot shutdownGestureRecognizer:(id)shutdown homeButtonType:(long long)type {
    id result = %orig;
    if (result) DSRegister(screenshot);
    return result;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    id down = DSObjectField(self, "_volumeDecreaseButtonPressGestureRecognizer");
    // Let the screenshot chord resolve before an ordinary volume-down action.
    if (down && gesture == down && DSIsScreenshot(other)) return YES;
    if (down && other == down && DSIsScreenshot(gesture)) return NO;
    return %orig;
}
%end

%hook SBClickGestureRecognizer
- (void)setAllowedPressTypes:(NSArray<NSNumber *> *)types {
    if (DSIsScreenshot(self)) types = DSIncludeVolumeDown(types);
    %orig(types);
}
%end
%end

%ctor {
    @autoreleasepool {
        if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion == 12) {
            %init(IOS12);
        }
    }
}
