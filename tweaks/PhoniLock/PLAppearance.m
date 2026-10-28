#import "PLAppearance.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

NSString * const PLPreferencesDomain = @"com.phoni.phonilock";
NSString * const PLPreferencesChanged = @"com.phoni.phonilock/changed";

NSDictionary *PLDefaults(void) {
    return @{@"Enabled": @NO, @"ClockFormat": @"system", @"DateFormat": @"EEEE, MMMM d",
             @"FontStyle": @"light", @"TimeSize": @64, @"DateSize": @20, @"TextSize": @16,
             @"TimeColor": @"#FFFFFF", @"DateColor": @"#FFFFFF", @"TextColor": @"#46FFB4",
             @"CustomText": @"", @"Alignment": @1, @"VerticalOffset": @0, @"LineGap": @4,
             @"HideTime": @NO, @"HideDate": @NO, @"HideCustomText": @NO,
             @"HideUnlockHint": @NO, @"HidePageDots": @NO, @"HideLockIcon": @NO,
             @"HideSystemSubtitle": @NO};
}

NSDictionary *PLReadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PLPreferencesDomain);
    NSDictionary *saved = CFBridgingRelease(CFPreferencesCopyMultiple(NULL,
        (__bridge CFStringRef)PLPreferencesDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    NSMutableDictionary *values = [PLDefaults() mutableCopy];
    if ([saved isKindOfClass:[NSDictionary class]]) {
        // Ignore unexpected types, including malformed externally edited preferences.
        for (NSString *key in PLDefaults()) {
            id value = saved[key];
            id fallback = values[key];
            if (([fallback isKindOfClass:[NSNumber class]] && [value isKindOfClass:[NSNumber class]]) ||
                ([fallback isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]])) values[key] = value;
        }
    }
    return [values copy];
}

CGFloat PLNumber(NSDictionary *settings, NSString *key, CGFloat minimum, CGFloat maximum) {
    id value = settings[key];
    double number = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : [PLDefaults()[key] doubleValue];
    if (!isfinite(number)) number = [PLDefaults()[key] doubleValue];
    return MAX(minimum, MIN(maximum, number));
}

UIColor *PLColor(NSString *value, UIColor *fallback) {
    if (![value isKindOfClass:[NSString class]]) return fallback;
    NSString *hex = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6 || [hex rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet]].location != NSNotFound) return fallback;
    unsigned int number = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&number]) return fallback;
    return [UIColor colorWithRed:((number >> 16) & 255) / 255.0 green:((number >> 8) & 255) / 255.0 blue:(number & 255) / 255.0 alpha:1];
}

static UIFont *PLFont(NSString *style, CGFloat size) {
    if ([style isEqualToString:@"mono"]) return [UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightRegular];
    if ([style isEqualToString:@"rounded"]) return [UIFont fontWithName:@"AvenirNext-Medium" size:size] ?: [UIFont systemFontOfSize:size];
    if ([style isEqualToString:@"serif"]) return [UIFont fontWithName:@"Georgia" size:size] ?: [UIFont systemFontOfSize:size];
    UIFontWeight weight = UIFontWeightLight;
    if ([style isEqualToString:@"regular"]) weight = UIFontWeightRegular;
    if ([style isEqualToString:@"bold"]) weight = UIFontWeightBold;
    if ([style isEqualToString:@"thin"]) weight = UIFontWeightUltraLight;
    return [UIFont systemFontOfSize:size weight:weight];
}

@implementation PLClockView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor clearColor];
        self.timeLabel = [UILabel new]; self.dateLabel = [UILabel new]; self.textLabel = [UILabel new];
        for (UILabel *label in @[self.timeLabel, self.dateLabel, self.textLabel]) {
            label.numberOfLines = 1;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.45;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            label.shadowColor = [UIColor colorWithWhite:0 alpha:0.3];
            label.shadowOffset = CGSizeMake(0, 1);
            label.isAccessibilityElement = YES;
            [self addSubview:label];
        }
    }
    return self;
}

- (void)renderPreferences:(NSDictionary *)settings date:(NSDate *)date systemSubtitleVisible:(BOOL)systemSubtitle {
    NSString *format = settings[@"ClockFormat"];
    NSString *dateFormat = settings[@"DateFormat"];
    if (![dateFormat isKindOfClass:[NSString class]] || dateFormat.length == 0 || dateFormat.length > 100) dateFormat = PLDefaults()[@"DateFormat"];
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%@", format, dateFormat, [NSLocale currentLocale].localeIdentifier, [NSTimeZone localTimeZone].name];
    if (![signature isEqualToString:self.formatSignature]) {
        self.formatSignature = signature;
        self.clockFormatter = [NSDateFormatter new];
        self.clockFormatter.locale = [NSLocale currentLocale]; self.clockFormatter.timeZone = [NSTimeZone localTimeZone];
        if ([format isEqualToString:@"24"]) self.clockFormatter.dateFormat = @"HH:mm";
        else if ([format isEqualToString:@"12"]) self.clockFormatter.dateFormat = @"h:mm";
        else if ([format isEqualToString:@"12ampm"]) self.clockFormatter.dateFormat = @"h:mm a";
        else self.clockFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:self.clockFormatter.locale];
        self.dateFormatter = [NSDateFormatter new];
        self.dateFormatter.locale = [NSLocale currentLocale]; self.dateFormatter.timeZone = [NSTimeZone localTimeZone];
        @try { self.dateFormatter.dateFormat = dateFormat; }
        @catch (__unused NSException *error) { self.dateFormatter.dateStyle = NSDateFormatterLongStyle; }
    }
    self.timeLabel.text = [self.clockFormatter stringFromDate:date];
    @try { self.dateLabel.text = [self.dateFormatter stringFromDate:date]; }
    @catch (__unused NSException *error) {
        self.dateFormatter = [NSDateFormatter new];
        self.dateFormatter.dateStyle = NSDateFormatterLongStyle;
        self.dateLabel.text = [self.dateFormatter stringFromDate:date];
    }
    NSString *custom = settings[@"CustomText"];
    if (![custom isKindOfClass:[NSString class]]) custom = @"";
    self.textLabel.text = custom.length > 160 ? [custom substringToIndex:160] : custom;
    self.timeLabel.hidden = [settings[@"HideTime"] boolValue];
    self.dateLabel.hidden = [settings[@"HideDate"] boolValue] || systemSubtitle;
    self.textLabel.hidden = [settings[@"HideCustomText"] boolValue] || custom.length == 0 || systemSubtitle;
    self.timeLabel.textColor = PLColor(settings[@"TimeColor"], [UIColor whiteColor]);
    self.dateLabel.textColor = PLColor(settings[@"DateColor"], [UIColor whiteColor]);
    self.textLabel.textColor = PLColor(settings[@"TextColor"], [UIColor whiteColor]);
    CGFloat sizes[] = {PLNumber(settings, @"TimeSize", 36, 100), PLNumber(settings, @"DateSize", 10, 32), PLNumber(settings, @"TextSize", 10, 28)};
    NSArray<UILabel *> *labels = @[self.timeLabel, self.dateLabel, self.textLabel];
    CGFloat total = 0, gap = PLNumber(settings, @"LineGap", 0, 16);
    NSInteger count = 0;
    for (NSUInteger index = 0; index < labels.count; index++) if (!labels[index].hidden) { total += sizes[index] * 1.3; count++; }
    total += MAX(0, count - 1) * gap;
    CGFloat height = MAX(1, self.bounds.size.height), scale = MIN(1, height / MAX(1, total));
    total *= scale;
    CGFloat y = MAX(0, MIN(height - total, (height - total) / 2 + PLNumber(settings, @"VerticalOffset", -40, 40)));
    NSInteger choice = (NSInteger)PLNumber(settings, @"Alignment", 0, 2);
    NSTextAlignment alignment = choice == 0 ? NSTextAlignmentLeft : (choice == 2 ? NSTextAlignmentRight : NSTextAlignmentCenter);
    for (NSUInteger index = 0; index < labels.count; index++) {
        UILabel *label = labels[index];
        label.font = PLFont(settings[@"FontStyle"], sizes[index] * scale);
        label.textAlignment = alignment;
        label.accessibilityLabel = label.text;
        if (label.hidden) continue;
        CGFloat lineHeight = sizes[index] * 1.3 * scale;
        label.frame = CGRectMake(18, y, MAX(1, self.bounds.size.width - 36), lineHeight);
        y += lineHeight + gap * scale;
    }
}
@end
