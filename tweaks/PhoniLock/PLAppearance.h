#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const PLPreferencesDomain;
FOUNDATION_EXPORT NSString * const PLPreferencesChanged;
FOUNDATION_EXPORT NSDictionary *PLDefaults(void);
FOUNDATION_EXPORT NSDictionary *PLReadPreferences(void);
FOUNDATION_EXPORT UIColor *PLColor(NSString *value, UIColor *fallback);
FOUNDATION_EXPORT CGFloat PLNumber(NSDictionary *settings, NSString *key, CGFloat minimum, CGFloat maximum);

@interface PLClockView : UIView
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) NSDateFormatter *clockFormatter;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, copy) NSString *formatSignature;
- (void)renderPreferences:(NSDictionary *)settings date:(NSDate *)date systemSubtitleVisible:(BOOL)visible;
@end
