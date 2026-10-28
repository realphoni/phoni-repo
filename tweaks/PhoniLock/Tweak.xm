#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#import "PLAppearance.h"

// These are iOS 12 classes. Resolve fields defensively so a missing view leaves
// the native lock screen intact instead of throwing a KVC exception.
@interface SBFLockScreenDateView : UIView
@property (nonatomic, retain) NSDate *date;
@end
@interface SBDashBoardFixedFooterView : UIView @end
@interface SBDashBoardTeachableMomentsContainerView : UIView @end
@interface SBDashBoardView : UIView @end

static NSDictionary *PLSettings;
static NSHashTable<UIView *> *PLTrackedViews;
static char PLOverlayKey, PLHiddenKey;

static UIView *PLField(id object, const char *name) {
    if (!object) return nil;
    Ivar field = class_getInstanceVariable([object class], name);
    if (!field || ivar_getTypeEncoding(field)[0] != '@') return nil;
    id value = object_getIvar(object, field);
    return [value isKindOfClass:[UIView class]] ? value : nil;
}

static void PLHide(UIView *view, BOOL hide) {
    if (!view) return;
    NSNumber *original = objc_getAssociatedObject(view, &PLHiddenKey);
    if (hide) {
        if (!original) objc_setAssociatedObject(view, &PLHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.hidden = YES;
    } else if (original) {
        view.hidden = original.boolValue;
        objc_setAssociatedObject(view, &PLHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void PLStyleClock(SBFLockScreenDateView *view) {
    [PLTrackedViews addObject:view];
    UIView *nativeTime = PLField(view, "_timeLabel"), *nativeDate = PLField(view, "_dateSubtitleView");
    UIView *systemSubtitle = PLField(view, "_customSubtitleView");
    PLClockView *overlay = objc_getAssociatedObject(view, &PLOverlayKey);
    BOOL enabled = [PLSettings[@"Enabled"] boolValue] && nativeTime && nativeDate;
    if (!enabled) {
        PLHide(nativeTime, NO); PLHide(nativeDate, NO); PLHide(systemSubtitle, NO);
        overlay.hidden = YES;
        return;
    }
    if (!overlay) {
        overlay = [[PLClockView alloc] initWithFrame:view.bounds];
        objc_setAssociatedObject(view, &PLOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view addSubview:overlay];
    }
    BOOL hideSubtitle = [PLSettings[@"HideSystemSubtitle"] boolValue];
    PLHide(systemSubtitle, hideSubtitle);
    BOOL statusVisible = !hideSubtitle && systemSubtitle && !systemSubtitle.hidden && systemSubtitle.alpha > 0.01;
    // The native date view owns minute ticks, wake updates, and preview dates.
    // No polling timer runs while the phone sleeps.
    NSDate *date = view.date ?: [NSDate date];
    overlay.frame = view.bounds;
    overlay.hidden = NO;
    [overlay renderPreferences:PLSettings date:date systemSubtitleVisible:statusVisible];
    overlay.timeLabel.alpha = nativeTime.alpha;
    overlay.dateLabel.alpha = hideSubtitle ? nativeTime.alpha : nativeDate.alpha;
    overlay.textLabel.alpha = hideSubtitle ? nativeTime.alpha : nativeDate.alpha;
    PLHide(nativeTime, YES); PLHide(nativeDate, YES);
    [view bringSubviewToFront:overlay];
}

static void PLStyleFooter(UIView *view) {
    [PLTrackedViews addObject:view];
    BOOL enabled = [PLSettings[@"Enabled"] boolValue];
    PLHide(PLField(view, "_callToActionLabel"), enabled && [PLSettings[@"HideUnlockHint"] boolValue]);
    PLHide(PLField(view, "_alternateCallToActionLabel"), enabled && [PLSettings[@"HideUnlockHint"] boolValue]);
    PLHide(PLField(view, "_pageControl"), enabled && [PLSettings[@"HidePageDots"] boolValue]);
}

static void PLStyleDashboard(UIView *view) {
    [PLTrackedViews addObject:view];
    PLHide(PLField(view, "_proudLockContainerView"), [PLSettings[@"Enabled"] boolValue] && [PLSettings[@"HideLockIcon"] boolValue]);
    // Do not change authentication, passcode views, gestures, or notification privacy.
}

static void PLReload(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    dispatch_async(dispatch_get_main_queue(), ^{
        PLSettings = PLReadPreferences();
        for (UIView *view in PLTrackedViews.allObjects) {
            if ([view isKindOfClass:NSClassFromString(@"SBFLockScreenDateView")]) PLStyleClock((SBFLockScreenDateView *)view);
            else if ([view isKindOfClass:NSClassFromString(@"SBDashBoardView")]) PLStyleDashboard(view);
            else PLStyleFooter(view);
            [view setNeedsLayout];
        }
    });
}

%group IOS12
%hook SBFLockScreenDateView
- (void)layoutSubviews { %orig; PLStyleClock(self); }
- (void)setDate:(NSDate *)date { %orig; PLStyleClock(self); }
- (void)didMoveToWindow { %orig; PLStyleClock(self); }
- (void)_updateLabelAlpha { %orig; PLStyleClock(self); }
%end
%hook SBDashBoardFixedFooterView
- (void)layoutSubviews { %orig; PLStyleFooter(self); }
%end
%hook SBDashBoardTeachableMomentsContainerView
- (void)layoutSubviews { %orig; PLStyleFooter(self); }
%end
%hook SBDashBoardView
- (void)layoutSubviews { %orig; PLStyleDashboard(self); }
%end
%end

%ctor {
    @autoreleasepool {
        if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion != 12) return;
        PLSettings = PLReadPreferences();
        PLTrackedViews = [NSHashTable weakObjectsHashTable];
        %init(IOS12);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            PLReload, (__bridge CFStringRef)PLPreferencesChanged, NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
}
