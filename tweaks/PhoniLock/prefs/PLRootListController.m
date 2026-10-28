#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../PLAppearance.h"

@interface PLRootListController : PSListController
@property (nonatomic, strong) PLClockView *preview;
@end

@implementation PLRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PhoniLock";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 190)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [UIColor colorWithRed:0.035 green:0.075 blue:0.06 alpha:1];
    self.preview = [[PLClockView alloc] initWithFrame:CGRectMake(0, 12, header.bounds.size.width, 156)];
    self.preview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.preview];
    UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(15, 166, header.bounds.size.width - 30, 18)];
    caption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    caption.text = @"Style preview · enable below to apply";
    caption.font = [UIFont systemFontOfSize:11]; caption.textColor = [UIColor lightGrayColor]; caption.textAlignment = NSTextAlignmentCenter;
    [header addSubview:caption];
    UITableView *table = [self respondsToSelector:@selector(table)] ? [self table] : nil;
    table.tableHeaderView = header;
    [self updatePreview];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self updatePreview]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self updatePreview]; }
- (void)updatePreview { [self.preview renderPreferences:PLReadPreferences() date:[NSDate date] systemSubtitleVisible:NO]; }
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    return PLReadPreferences()[key] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)PLPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PLPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PLPreferencesChanged, NULL, NULL, YES);
    [self updatePreview];
}
- (void)resetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset PhoniLock?" message:@"This clears your choices and turns the tweak off." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        for (NSString *key in PLDefaults()) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)PLPreferencesDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)PLPreferencesDomain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)PLPreferencesChanged, NULL, NULL, YES);
        [self reloadSpecifiers]; [self updatePreview];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
