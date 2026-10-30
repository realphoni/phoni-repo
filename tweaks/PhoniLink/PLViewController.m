#import "PLViewController.h"
#import "PLCallManager.h"

static UIColor *PLMint(void) { return [UIColor colorWithRed:0.30 green:1 blue:0.74 alpha:1]; }
static UIColor *PLBackground(void) { return [UIColor colorWithRed:0.035 green:0.065 blue:0.055 alpha:1]; }

@interface PLViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property(nonatomic) PLCallManager *calls;
@property(nonatomic) UITextField *nameField;
@property(nonatomic) UIButton *nearbyButton, *answerButton, *endButton, *muteButton, *speakerButton;
@property(nonatomic) UILabel *statusLabel, *identityLabel, *peerHeading;
@property(nonatomic) UIStackView *callButtons, *audioButtons;
@property(nonatomic) UITableView *table;
@end

@implementation PLViewController
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal]; [button setTitleColor:PLMint() forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.075]; button.layer.cornerRadius = 12;
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [button.heightAnchor constraintEqualToConstant:46].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
- (UILabel *)label:(NSString *)text size:(CGFloat)size {
    UILabel *label = [UILabel new]; label.text = text; label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:size]; label.numberOfLines = 0; return label;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = PLBackground(); self.calls = [PLCallManager new];
    UILabel *title = [self label:@"PhoniLink" size:34]; title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    UILabel *intro = [self label:@"a little phone call, over Wi-Fi :)" size:15]; intro.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    self.nameField = [UITextField new]; self.nameField.textColor = [UIColor whiteColor]; self.nameField.tintColor = PLMint();
    self.nameField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"give this phone a name" attributes:@{NSForegroundColorAttributeName: [UIColor lightGrayColor]}];
    self.nameField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"phoneName"] ?: @"my iPhone";
    self.nameField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.075]; self.nameField.layer.cornerRadius = 12;
    UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)]; self.nameField.leftView = padding; self.nameField.leftViewMode = UITextFieldViewModeAlways;
    self.nameField.delegate = self; self.nameField.returnKeyType = UIReturnKeyDone; self.nameField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.nameField.heightAnchor constraintEqualToConstant:44].active = YES;
    self.nearbyButton = [self button:@"Turn on nearby calling" action:@selector(toggleNearby)];
    self.identityLabel = [self label:@"" size:12]; self.identityLabel.textColor = [UIColor lightGrayColor]; self.identityLabel.hidden = YES;
    self.statusLabel = [self label:self.calls.status size:17]; self.statusLabel.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
    self.answerButton = [self button:@"Answer" action:@selector(answer)]; self.endButton = [self button:@"Hang up" action:@selector(end)];
    [self.endButton setTitleColor:[UIColor colorWithRed:1 green:0.45 blue:0.44 alpha:1] forState:UIControlStateNormal];
    self.callButtons = [[UIStackView alloc] initWithArrangedSubviews:@[self.answerButton, self.endButton]];
    self.callButtons.axis = UILayoutConstraintAxisHorizontal; self.callButtons.distribution = UIStackViewDistributionFillEqually; self.callButtons.spacing = 10;
    self.muteButton = [self button:@"Mute" action:@selector(mute)]; self.speakerButton = [self button:@"Speaker" action:@selector(speaker)];
    self.audioButtons = [[UIStackView alloc] initWithArrangedSubviews:@[self.muteButton, self.speakerButton]];
    self.audioButtons.axis = UILayoutConstraintAxisHorizontal; self.audioButtons.distribution = UIStackViewDistributionFillEqually; self.audioButtons.spacing = 10;
    self.peerHeading = [self label:@"NEARBY PHONES" size:12]; self.peerHeading.textColor = PLMint();
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = [UIColor clearColor]; self.table.dataSource = self; self.table.delegate = self;
    self.table.separatorColor = [UIColor colorWithWhite:1 alpha:0.12]; self.table.tableFooterView = [UIView new]; self.table.rowHeight = 60;
    [self.table.heightAnchor constraintEqualToConstant:150].active = YES;
    UILabel *note = [self label:@"First beta: keep both apps open on the same Wi-Fi. Allow Microphone and Local Network when asked. Nearby transport can also use peer-to-peer Wi-Fi. No SIM or internet service needed." size:12];
    note.textColor = [UIColor colorWithWhite:0.63 alpha:1];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, intro, self.nameField, self.nearbyButton,
        self.identityLabel, self.statusLabel, self.callButtons, self.audioButtons, self.peerHeading, self.table, note]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll]; [scroll addSubview:stack]; UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor], [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-18],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-22],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-44]]];
    __weak PLViewController *weak = self; self.calls.changed = ^{ [weak refresh]; }; [self refresh];
}
- (void)refresh {
    PLCallManager *calls = self.calls;
    self.statusLabel.text = calls.remoteName.length ? [NSString stringWithFormat:@"%@\n%@", calls.remoteName, calls.status] : calls.status;
    self.identityLabel.hidden = !calls.nearbyEnabled; self.identityLabel.text = [@"This phone: " stringByAppendingString:calls.localName ?: @""];
    self.nameField.enabled = !calls.nearbyEnabled;
    [self.nearbyButton setTitle:calls.nearbyEnabled ? @"Turn off nearby calling" : @"Turn on nearby calling" forState:UIControlStateNormal];
    self.callButtons.hidden = calls.state == PLCallIdle;
    self.answerButton.hidden = calls.state != PLCallIncoming;
    [self.endButton setTitle:calls.state == PLCallIncoming ? @"Decline" : @"Hang up" forState:UIControlStateNormal];
    self.audioButtons.hidden = calls.state != PLCallActive;
    [self.muteButton setTitle:calls.muted ? @"Unmute" : @"Mute" forState:UIControlStateNormal];
    [self.speakerButton setTitle:calls.speaker ? @"Use earpiece" : @"Speaker" forState:UIControlStateNormal];
    self.peerHeading.text = calls.peers.count ? @"NEARBY PHONES · TAP TO CALL" : @"NO PHONES FOUND YET";
    [self.table reloadData];
}
- (void)toggleNearby {
    [self.nameField resignFirstResponder];
    if (self.calls.nearbyEnabled) [self.calls stopNearby]; else [self.calls startNearbyWithName:self.nameField.text];
}
- (void)answer { [self.calls answer]; }
- (void)end { [self.calls hangUp]; }
- (void)mute { [self.calls toggleMute]; }
- (void)speaker { [self.calls toggleSpeaker]; }
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return self.calls.peers.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"phone"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"phone"];
    MCPeerID *peer = self.calls.peers[index.row]; cell.textLabel.text = peer.displayName;
    cell.detailTextLabel.text = @"PhoniLink · audio call"; cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [UIColor whiteColor]; cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.tintColor = PLMint();
    cell.selectionStyle = self.calls.state == PLCallIdle ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.row >= (NSInteger)self.calls.peers.count || self.calls.state != PLCallIdle) return;
    MCPeerID *peer = self.calls.peers[index.row];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:[@"Call " stringByAppendingString:peer.displayName]
        message:@"Check that this name matches the other phone. Both apps need to stay open." preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Call" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { (void)action; [self.calls callPeer:peer]; }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
@end
