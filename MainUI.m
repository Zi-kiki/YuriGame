#import "MainUI.h"

@interface ImportVC()
@property (nonatomic, strong) ImportVC *rootVC;
@end

@implementation TSRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupBackground];
    [self setupTabs];
    [self setupAppearance];
}

- (void)setupBackground {
    self.bgImageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.bgImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.bgImageView.contentMode = UIViewContentModeScaleAspectFill;
    [self.view insertSubview:self.bgImageView atIndex:0];
    
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:@"wallpaper"];
    self.bgImageView.image = data ? [UIImage imageWithData:data] : [UIImage imageNamed:@"default_bg"];
}

- (void)setupTabs {
    UIViewController *vc1 = [self wrap:[TSAppTableViewController new] title:@"游戏库" image:@"gamecontroller"];
    UIViewController *vc2 = [self wrap:[ImportVC new] title:@"导入游戏" image:@"tray.and.arrow.down"];
    UIViewController *vc3 = [self wrap:[TSSettingsListController new] title:@"设置" image:@"gearshape"];
    
    self.viewControllers = @[vc1, vc2, vc3];
}

- (UINavigationController *)wrap:(UIViewController *)vc title:(NSString *)title image:(NSString *)imageName {
    vc.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.tabBarItem.title = title;
    nav.tabBarItem.image = [UIImage systemImageNamed:imageName];
    return nav;
}

- (void)setupAppearance {
    UINavigationBarAppearance *navAppearance = [UINavigationBarAppearance new];
    [navAppearance configureWithTransparentBackground];
    navAppearance.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.6];
    
    for (UINavigationController *nav in self.viewControllers) {
        nav.navigationBar.standardAppearance = navAppearance;
        nav.navigationBar.scrollEdgeAppearance = navAppearance;
    }
    
    UITabBarAppearance *tabAppearance = [UITabBarAppearance new];
    [tabAppearance configureWithTransparentBackground];
    tabAppearance.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.6];
    self.tabBar.standardAppearance = tabAppearance;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    
    if (img) {
        NSData *data = UIImageJPEGRepresentation(img, 1.0);
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"wallpaper"];
        self.bgImageView.image = img;
    }
    
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation TSAppTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTable];
    [self loadAppexFiles];
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)loadAppexFiles {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *pluginsURL = [[NSBundle mainBundle] builtInPlugInsURL];
    NSArray *contents = [fileManager contentsOfDirectoryAtURL:pluginsURL
                                   includingPropertiesForKeys:nil
                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        error:nil];
    
    NSMutableArray *appexFiles = [NSMutableArray array];
    for (NSURL *url in contents) {
        if ([[url pathExtension] isEqualToString:@"appex"]) {
            [appexFiles addObject:[url lastPathComponent]];
        }
    }
    
    self.appexFiles = [appexFiles copy];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.appexFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppexCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AppexCell"];
    }
    
    cell.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.6];
    cell.textLabel.text = self.appexFiles[indexPath.row];
    cell.textLabel.textColor = UIColor.labelColor;
    
    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [playButton setImage:[UIImage systemImageNamed:@"play.circle.fill"] forState:UIControlStateNormal];
    playButton.frame = CGRectMake(0, 0, 44, 44);
    playButton.tag = indexPath.row;
    [playButton addTarget:self action:@selector(playButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = playButton;
    
    return cell;
}

- (void)playButtonTapped:(UIButton *)sender {
    if (sender.tag < self.appexFiles.count) {
        NSString *selectedAppex = self.appexFiles[sender.tag];
        [[NSUserDefaults standardUserDefaults] setObject:selectedAppex forKey:@"selected"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self attemptOpenURLWithCount:0];
    }
}

- (void)attemptOpenURLWithCount:(NSInteger)count {
    NSURL *url = [NSURL URLWithString:@"yurigame://"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (success) {
                exit(0);
            } else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self attemptOpenURLWithCount:count + 1];
                });
            }
        }];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self attemptOpenURLWithCount:count + 1];
        });
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

@end

@implementation ImportVC

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTable];
    [self setupNavigation];
    
    if (!self.rootVC) {
        self.rootVC = (ImportVC *)self.navigationController.viewControllers.firstObject;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updatePasteButton];
    [self updateTitle];
    [self loadFiles];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.tableView setEditing:NO animated:YES];
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (void)setupNavigation {
    if (self.navigationController.viewControllers.count > 1) {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)updateTitle {
    if (self.currentURL) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *documentsURL = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        if ([self.currentURL isEqual:documentsURL]) {
            self.title = @"导入游戏";
        } else {
            self.title = [self.currentURL lastPathComponent];
        }
    } else {
        self.title = @"导入游戏";
    }
}

- (void)updatePasteButton {
    ImportVC *rootVC = (ImportVC *)self.rootVC;
    
    if (rootVC.moveFromURL) {
        if (!self.pasteButton) {
            self.pasteButton = [[UIBarButtonItem alloc] initWithTitle:@"粘贴" style:UIBarButtonItemStylePlain target:self action:@selector(pasteAction)];
        }
        
        if (!self.cancelButton) {
            self.cancelButton = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancelMoveAction)];
        }
        
        self.navigationItem.rightBarButtonItems = @[self.pasteButton, self.cancelButton];
    } else {
        self.navigationItem.rightBarButtonItems = nil;
    }
}

- (void)loadFiles {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *baseURL = self.currentURL ?: [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    self.currentURL = baseURL;
    
    NSError *error;
    NSArray *contents = [fileManager contentsOfDirectoryAtURL:baseURL
                                  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                       error:&error];
    
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    
    for (NSURL *url in contents) {
        NSNumber *isDir;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            [folders addObject:url];
        } else {
            [files addObject:url];
        }
    }
    
    [folders sortUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
        return [url1.lastPathComponent compare:url2.lastPathComponent];
    }];
    
    [files sortUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
        return [url1.lastPathComponent compare:url2.lastPathComponent];
    }];
    
    self.files = [NSMutableArray array];
    for (NSURL *url in folders) {
        NSNumber *isDir;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        [self.files addObject:@[url.lastPathComponent, url, isDir]];
    }
    for (NSURL *url in files) {
        NSNumber *isDir;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        [self.files addObject:@[url.lastPathComponent, url, isDir]];
    }
    
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.files.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FileCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"FileCell"];
    }
    
    NSArray *item = self.files[indexPath.row];
    NSString *name = item[0];
    NSNumber *isDir = item[2];
    
    cell.backgroundColor = [UIColor systemBackgroundColor];
    cell.textLabel.text = name;
    cell.imageView.image = [UIImage systemImageNamed:isDir.boolValue ? @"folder" : @"doc"];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSArray *item = self.files[indexPath.row];
    NSURL *url = item[1];
    NSNumber *isDir = item[2];
    
    if (isDir.boolValue) {
        ImportVC *subVC = [ImportVC new];
        subVC.currentURL = url;
        subVC.rootVC = self.rootVC;
        [self.navigationController pushViewController:subVC animated:YES];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        NSArray *item = self.files[indexPath.row];
        NSURL *url = item[1];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtURL:url error:nil];
        [self.files removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        completionHandler(YES);
    }];
    
    UIContextualAction *moveAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"移动" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        ImportVC *rootVC = (ImportVC *)self.rootVC;
        rootVC.moveFromURL = self.files[indexPath.row][1];
        
        [self updatePasteButton];
        [rootVC updatePasteButton];
        completionHandler(YES);
    }];
    moveAction.backgroundColor = [UIColor systemBlueColor];
    
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, moveAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (void)pasteAction {
    ImportVC *rootVC = (ImportVC *)self.rootVC;
    
    if (rootVC.moveFromURL && self.currentURL) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *toURL = [self.currentURL URLByAppendingPathComponent:rootVC.moveFromURL.lastPathComponent];
        
        [fileManager moveItemAtURL:rootVC.moveFromURL toURL:toURL error:nil];
        
        rootVC.moveFromURL = nil;
        
        [self loadFiles];
        
        for (UIViewController *vc in self.navigationController.viewControllers) {
            if ([vc isKindOfClass:[ImportVC class]]) {
                [(ImportVC *)vc updatePasteButton];
            }
        }
    }
}

- (void)cancelMoveAction {
    ImportVC *rootVC = (ImportVC *)self.rootVC;
    rootVC.moveFromURL = nil;
    
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:[ImportVC class]]) {
            [(ImportVC *)vc updatePasteButton];
        }
    }
}

@end

@implementation TSSettingsListController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTable];
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    cell.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.6];
    
    if (indexPath.section == 0) {
        cell.textLabel.text = @"自定义主题";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"版本";
                cell.detailTextLabel.text = @"1.0";
                break;
            case 1:
                cell.textLabel.text = @"作者";
                cell.detailTextLabel.text = @"KoiYuri";
                break;
            default:
                cell.textLabel.text = @"QQ群";
                cell.detailTextLabel.text = @"3142499905";
                break;
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 0 && indexPath.row == 0) {
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.delegate = (id)self.tabBarController;
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

@end
