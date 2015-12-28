/*****************************************************************************
 * VLCOpenNetworkStreamViewController.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2013-2015 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan.org>
 *          Gleb Pinigin <gpinigin # gmail.com>
 *          Pierre Sagaspe <pierre.sagaspe # me.com>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import "VLCOpenNetworkStreamViewController.h"
#import "VLCPlaybackController.h"
#import "VLCLibraryViewController.h"
#import "VLCMenuTableViewController.h"
#import "UIDevice+VLC.h"

@interface VLCOpenNetworkStreamViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
{
    NSMutableArray *_recentURLs;
}
@end

@implementation VLCOpenNetworkStreamViewController

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSDictionary *appDefaults = @{kVLCRecentURLs : @[], kVLCPrivateWebStreaming : @(NO)};

    [defaults registerDefaults:appDefaults];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self updatePasteboardTextInURLField];
}

- (void)ubiquitousKeyValueStoreDidChange:(NSNotification *)notification
{
    /* TODO: don't blindly trust that the Cloud knows best */
    _recentURLs = [NSMutableArray arrayWithArray:[[NSUbiquitousKeyValueStore defaultStore] arrayForKey:kVLCRecentURLs]];
    [self.historyTableView reloadData];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(ubiquitousKeyValueStoreDidChange:)
                               name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification
                             object:[NSUbiquitousKeyValueStore defaultStore]];

    /* force store update */
    NSUbiquitousKeyValueStore *ubiquitousKeyValueStore = [NSUbiquitousKeyValueStore defaultStore];
    [ubiquitousKeyValueStore synchronize];

    /* fetch data from cloud */
    _recentURLs = [NSMutableArray arrayWithArray:[[NSUbiquitousKeyValueStore defaultStore] arrayForKey:kVLCRecentURLs]];

    /* merge data from local storage (aka legacy VLC versions) */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *localRecentUrls = [defaults objectForKey:kVLCRecentURLs];
    if (localRecentUrls != nil) {
        if (localRecentUrls.count != 0) {
            [_recentURLs addObjectsFromArray:localRecentUrls];
            [defaults setObject:nil forKey:kVLCRecentURLs];
            [ubiquitousKeyValueStore setArray:_recentURLs forKey:kVLCRecentURLs];
            [ubiquitousKeyValueStore synchronize];
        }
    }

    /*
     * Observe changes to the pasteboard so we can automatically paste it into the URL field.
     * Do not use UIPasteboardChangedNotification because we have copy actions that will trigger it on this screen.
     * Instead when the user comes back to the application from the background (or the inactive state by pulling down notification center), update the URL field.
     * Using the 'active' rather than 'foreground' notification for future proofing if iOS ever allows running multiple apps on the same screen (which would allow the pasteboard to be changed without truly backgrounding the app).
     */
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActive:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:[UIApplication sharedApplication]];

    [self.openButton setTitle:NSLocalizedString(@"OPEN_NETWORK", nil) forState:UIControlStateNormal];
    [self.privateModeLabel setText:NSLocalizedString(@"PRIVATE_PLAYBACK_TOGGLE", nil)];
    UILabel *scanSubModelabel = self.ScanSubModeLabel;
    [scanSubModelabel setText:NSLocalizedString(@"SCAN_SUBTITLE_TOGGLE", nil)];
    [scanSubModelabel setAdjustsFontSizeToFitWidth:YES];
    [scanSubModelabel setNumberOfLines:0];
    self.title = NSLocalizedString(@"OPEN_NETWORK", nil);
    self.navigationItem.leftBarButtonItem = [UIBarButtonItem themedRevealMenuButtonWithTarget:self andSelector:@selector(goBack:)];
    [self.whatToOpenHelpLabel setText:NSLocalizedString(@"OPEN_NETWORK_HELP", nil)];
    self.urlField.delegate = self;
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.historyTableView.backgroundColor = [UIColor VLCDarkBackgroundColor];

    NSAttributedString *coloredAttributedPlaceholder = [[NSAttributedString alloc] initWithString:@"http://myserver.com/file.mkv" attributes:@{NSForegroundColorAttributeName: [UIColor VLCLightTextColor]}];
    self.urlField.attributedPlaceholder = coloredAttributedPlaceholder;
    self.edgesForExtendedLayout = UIRectEdgeNone;

    // This will be called every time this VC is opened by the side menu controller
    [self updatePasteboardTextInURLField];
}

- (void)updatePasteboardTextInURLField
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if ([pasteboard containsPasteboardTypes:@[@"public.url"]])
        self.urlField.text = [[pasteboard valueForPasteboardType:@"public.url"] absoluteString];
}

- (void)viewWillAppear:(BOOL)animated
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.privateToggleSwitch.on = [defaults boolForKey:kVLCPrivateWebStreaming];
    self.ScanSubToggleSwitch.on = [defaults boolForKey:kVLChttpScanSubtitle];

    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:[UIApplication sharedApplication]];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.privateToggleSwitch.on forKey:kVLCPrivateWebStreaming];
    [defaults setBool:self.ScanSubToggleSwitch.on forKey:kVLChttpScanSubtitle];
    [defaults synchronize];

    /* force update before we leave */
    [[NSUbiquitousKeyValueStore defaultStore] synchronize];

    [super viewWillDisappear:animated];
}

- (CGSize)contentSizeForViewInPopover {
    return [self.view sizeThatFits:CGSizeMake(320, 800)];
}

#pragma mark - UI interaction
- (BOOL)shouldAutorotate
{
    UIInterfaceOrientation toInterfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone && toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)
        return NO;
    return YES;
}

- (IBAction)goBack:(id)sender
{
    [self.view endEditing:YES];
    [[VLCSidebarController sharedInstance] toggleSidebar];
}

- (IBAction)openButtonAction:(id)sender
{
    if ([self.urlField.text length] > 0) {
        if (!self.privateToggleSwitch.on) {
            NSString *urlString = self.urlField.text;
            if ([_recentURLs indexOfObject:urlString] != NSNotFound)
                [_recentURLs removeObject:urlString];

            if (_recentURLs.count >= 100)
                [_recentURLs removeLastObject];
            [_recentURLs addObject:urlString];
            [[NSUbiquitousKeyValueStore defaultStore] setArray:_recentURLs forKey:kVLCRecentURLs];

            [self.historyTableView reloadData];
        }
        [self.urlField resignFirstResponder];
        [self performSelectorInBackground:@selector(_openURLStringAndDismiss:) withObject:self.urlField.text];
    }
}

#pragma mark - table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _recentURLs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"StreamingHistoryCell";

    UITableViewCell *cell = (UITableViewCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.highlightedTextColor = [UIColor blackColor];
        cell.detailTextLabel.textColor = [UIColor VLCLightTextColor];
        cell.detailTextLabel.highlightedTextColor = [UIColor blackColor];
    }

    NSString *content = [_recentURLs[indexPath.row] stringByRemovingPercentEncoding];
    cell.textLabel.text = [content lastPathComponent];
    cell.detailTextLabel.text = content;

    return cell;
}

#pragma mark - table view delegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    cell.backgroundColor = (indexPath.row % 2 == 0)? [UIColor blackColor]: [UIColor VLCDarkBackgroundColor];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [_recentURLs removeObjectAtIndex:indexPath.row];
        [[NSUbiquitousKeyValueStore defaultStore] setArray:_recentURLs forKey:kVLCRecentURLs];
        [tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.historyTableView deselectRowAtIndexPath:indexPath animated:NO];
    [self performSelectorInBackground:@selector(_openURLStringAndDismiss:) withObject:_recentURLs[indexPath.row]];
}

- (void)tableView:(UITableView *)tableView
    performAction:(SEL)action
forRowAtIndexPath:(NSIndexPath *)indexPath
       withSender:(id)sender
{
    NSString *actionText = NSStringFromSelector(action);

    if ([actionText isEqualToString:@"copy:"])
        [UIPasteboard generalPasteboard].string = _recentURLs[indexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView
 canPerformAction:(SEL)action
forRowAtIndexPath:(NSIndexPath *)indexPath
       withSender:(id)sender
{
    NSString *actionText = NSStringFromSelector(action);

    if ([actionText isEqualToString:@"copy:"])
        return YES;

    return NO;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

#pragma mark - internals
- (void)_openURLStringAndDismiss:(NSString *)url
{
    NSURL *URLscheme = [NSURL URLWithString:url];
    NSString *URLofSubtitle = nil;

    if ([URLscheme.scheme isEqualToString:@"http"])
        if (self.ScanSubToggleSwitch.on)
            URLofSubtitle = [self _checkURLofSubtitle:url];

    VLCPlaybackController *vpc = [VLCPlaybackController sharedInstance];
    [vpc playURL:[NSURL URLWithString:url] subtitlesFilePath:URLofSubtitle];
}

- (NSString *)_checkURLofSubtitle:(NSString *)url
{
    NSCharacterSet *characterFilter = [NSCharacterSet characterSetWithCharactersInString:@"\\.():$"];
    NSString *subtitleFileExtensions = [[kSupportedSubtitleFileExtensions componentsSeparatedByCharactersInSet:characterFilter] componentsJoinedByString:@""];
    NSArray *arraySubtitleFileExtensions = [subtitleFileExtensions componentsSeparatedByString:@"|"];
    NSString *urlTemp = [[url stringByDeletingPathExtension] stringByAppendingString:@"."];
    NSUInteger count = arraySubtitleFileExtensions.count;

    for (int i = 0; i < count; i++) {
        NSString *checkAddress = [urlTemp stringByAppendingString:arraySubtitleFileExtensions[i]];
        NSURL *checkURL = [NSURL URLWithString:checkAddress];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:checkURL];
        request.HTTPMethod = @"HEAD";

        NSURLResponse *response = nil;
        [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
        NSInteger httpStatus = [(NSHTTPURLResponse *)response statusCode];

        if (httpStatus == 200) {
            NSString *fileSubtitlePath = [self _getFileSubtitleFromServer:checkURL];
            return fileSubtitlePath;
        }
    }
    return nil;
}

- (NSString *)_getFileSubtitleFromServer:(NSURL *)url
{
    NSString *fileSubtitlePath = nil;
    NSString *fileName = [[url path] lastPathComponent];
    NSData *receivedSub = [NSData dataWithContentsOfURL:url];

    if (receivedSub.length < [[UIDevice currentDevice] freeDiskspace].longLongValue) {
        NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *directoryPath = [searchPaths objectAtIndex:0];
        fileSubtitlePath = [directoryPath stringByAppendingPathComponent:fileName];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:fileSubtitlePath]) {
            [fileManager createFileAtPath:fileSubtitlePath contents:nil attributes:nil];
            if (![fileManager fileExistsAtPath:fileSubtitlePath])
                APLog(@"file creation failed, no data was saved");
        }
        [receivedSub writeToFile:fileSubtitlePath atomically:YES];
    } else {
        VLCAlertView *alert = [[VLCAlertView alloc] initWithTitle:NSLocalizedString(@"DISK_FULL", nil)
                                                          message:[NSString stringWithFormat:NSLocalizedString(@"DISK_FULL_FORMAT", nil), fileName, [[UIDevice currentDevice] model]]
                                                         delegate:self
                                                cancelButtonTitle:NSLocalizedString(@"BUTTON_OK", nil)
                                                otherButtonTitles:nil];
        [alert performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:NO];
    }

    return fileSubtitlePath;
}

#pragma mark - text view delegate
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.urlField resignFirstResponder];
    return NO;
}

@end
