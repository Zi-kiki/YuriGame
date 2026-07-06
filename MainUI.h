#import <UIKit/UIKit.h>

@interface TSRootViewController : UITabBarController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIImageView *bgImageView;
@end

@interface TSAppTableViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *appexFiles;
- (void)attemptOpenURLWithCount:(NSInteger)count;
@end

@interface ImportVC : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *files;
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, strong) NSURL *moveFromURL;
@property (nonatomic, strong) UIBarButtonItem *pasteButton;
@property (nonatomic, strong) UIBarButtonItem *cancelButton;
@end

@interface TSSettingsListController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end
