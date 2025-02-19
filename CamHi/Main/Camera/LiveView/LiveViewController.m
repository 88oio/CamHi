//
//  LiveViewController.m
//  CamHi
//
//  Created by HXjiang on 16/7/19.
//  Copyright © 2016年 JiangLin. All rights reserved.
//

#import "LiveViewController.h"
#import "ToolBar.h"
#import "MirrorView.h"
#import "ZoomFocusDialog.h"
#import "PresetDialog.h"
#import "Microphone.h"
#import "Recording.h"
#import "QualityDialog.h"
#import "iToast.h"
#import "WhiteLightView.h"

#import "LiveModel.h"


#define SMONITOR    (100)


typedef NS_ENUM(NSInteger, SwipeDirection) {
    SwipeDirectionNone,
    SwipeDirectionUp,
    SwipeDirectionDown,
    SwipeDirectionRight,
    SwipeDirectionLeft,
};


typedef NS_ENUM(NSInteger, DeviceOrientation) {
    DeviceOrientationUnknown,
    DeviceOrientationPortrait,
    DeviceOrientationLandscapeLeft,
    DeviceOrientationLandscapeRight
};



@interface LiveViewController ()
<ToolBarDelegate>
{
    BOOL isFullScreen;
    CGFloat WIDTH;
    CGFloat HEIGHT;
    double ptz_ctrl_time;

    DeviceOrientation deviceOrientation;
    QualityType qualityType;
}

@property (nonatomic, assign) BOOL isShowing;

// model
@property (nonatomic, strong) __block Display *display;
@property (nonatomic, strong) __block TimeParam *timeParam;

// view
@property (nonatomic, strong) UIScrollView *smonitor;
@property (nonatomic, strong) HiGLMonitor *monitor;

@property (nonatomic, strong) ToolBar *topToolBar;
@property (nonatomic, strong) ToolBar *bottomToolBar;
@property (nonatomic, strong) MirrorView *mirror;
@property (nonatomic, strong) ZoomFocusDialog *zoomfocus;
@property (nonatomic, strong) PresetDialog *preset;
@property (nonatomic, strong) Microphone *microphone;
@property (nonatomic, strong) Recording *record;
@property (nonatomic, strong) QualityDialog *quality;
@property (nonatomic, strong) WhiteLightView *lightView;
@property (nonatomic, strong) NSMutableArray *topLiveModels;
@property (nonatomic, strong) NSMutableArray *bottomLiveModels;

@end

@implementation LiveViewController

#pragma mark - viewDidLoad
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    
    [self.camera registerIOSessionDelegate:self];

    [self setupView];
    [self setup];
    
    //注册屏幕旋转通知
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarOrientationsDidChange:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    //强制横屏
//    [self forceChangeToOrientation:UIInterfaceOrientationLandscapeRight];
   // self.view.transform = CGAffineTransformRotate(CGAffineTransformIdentity, M_PI_2);

}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.tabBarController.tabBar.hidden = YES;
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    self.tabBarController.tabBar.hidden = NO;
    self.navigationController.navigationBarHidden = NO;
    
    //stop live
    //[self.camera stopLiveShow];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];

    //delete all views
//    for (UIView *v in self.view.subviews) {
//        [v removeFromSuperview];
//    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (BOOL)prefersStatusBarHidden {
    return YES;
}


#pragma mark - setup
- (void)setup {
    
    // 连接图像时，摄像机时间自动同步为手机时间
    [self syncWithPhoneTime];

    
    if ([self.camera getCommandFunction:HI_P2P_GET_DISPLAY_PARAM]) {
        [self.camera request:HI_P2P_GET_DISPLAY_PARAM dson:nil];
    }
    
    __weak typeof(self) weakSelf = self;
    
    self.camera.cmdBlock = ^(BOOL success, NSInteger cmd, NSDictionary *dic) {
      
        if (cmd == HI_P2P_GET_DISPLAY_PARAM) {
            weakSelf.display = [weakSelf.camera object:dic];
            
            weakSelf.mirror.switchMirror.on = weakSelf.display.u32Mirror == 1 ? YES : NO;
            weakSelf.mirror.switchFlip.on = weakSelf.display.u32Flip == 1 ? YES : NO;

        }// @镜像翻转
        
        if (cmd == HI_P2P_WHITE_LIGHT_GET) {
            
            [weakSelf.topLiveModels enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                
                LiveModel *t_live = (LiveModel *)obj;
                if ([t_live.normalImgName isEqualToString:@"light_gray"]) {
                    
                    if (weakSelf.camera.whiteLight.u32State == 0) {
                        [weakSelf.topToolBar setSelect:NO atIndex:(int)idx];
                    }
                    
                    if (weakSelf.camera.whiteLight.u32State == 1) {
                        [weakSelf.topToolBar setSelect:YES atIndex:(int)idx];
                    }

                }
            }];
            
        }// 白光灯开关
        
        
        if (cmd == HI_P2P_WHITE_LIGHT_GET_EXT) {
            
            [weakSelf.lightView reloadWithIndex:(NSInteger)weakSelf.camera.whiteLight.u32State];
        }
        
        
    };// @cmdBlock

    
    qualityType = QualityTypeNone;
    
    
    //连接状态
    self.camera.connectBlock = ^(NSInteger state, NSString *connection) {
      
        if (state == CAMERA_CONNECTION_STATE_LOGIN) {
            
            [HXProgress dismiss];
            
            if (qualityType == QualityTypeHigh) {
                
                [weakSelf.camera startLiveShow:0 Monitor:weakSelf.monitor];
            }
            
            if (qualityType == QualityTypeLow) {
                
                [weakSelf.camera startLiveShow:1 Monitor:weakSelf.monitor];
            }

        }
        
    };// @connectBlock
    
    
    _isShowing = NO;
    // 画面显示状态/录像状态
    self.camera.playStateBlock = ^(NSInteger state) {
        
        if (state == 0) {
            weakSelf.isShowing = YES;
        }
    };
    
    //注册通知，进入后台时退回主界面
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:UIApplicationWillResignActiveNotification object:nil];
  
}


- (void)syncWithPhoneTime {
    
    _timeParam = [[TimeParam alloc] init];
    [_timeParam syncCurrentTime];
    
    [self.camera request:HI_P2P_SET_TIME_PARAM dson:[self.camera dic:_timeParam]];
}



- (void)didReceiveNotification:(NSNotification *)notification {
    
    LOG(@"LiveView_didReceiveNotification : %@", notification.name)
    [self exit];
//    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
}




- (void)setupView {
    
    ptz_ctrl_time = 0;
    
    WIDTH   = [UIScreen mainScreen].bounds.size.width;
    HEIGHT  = [UIScreen mainScreen].bounds.size.height;
    
    deviceOrientation = DeviceOrientationPortrait;
    
    
    
    
    
    
    
    
    //isFullScreen = NO;
    [self setupMonitor:isFullScreen];
    [self setupTopToolBar:isFullScreen];
    [self setupBottomToolBar:isFullScreen];
    
    
    [self.view addSubview:self.mirror];
    [self.view addSubview:self.zoomfocus];
    [self.view addSubview:self.preset];
    [self.view addSubview:self.microphone];
    [self.view addSubview:self.record];
    [self.view addSubview:self.quality];
    
    if ([self.camera getCommandFunction:HI_P2P_WHITE_LIGHT_GET_EXT]) {
        [self.view addSubview:self.lightView];
        
    }// 夜视模式选择
    
    
    
//    UIDeviceOrientation currentOrientation = [UIDevice currentDevice].orientation;
//    
//    
//    if (currentOrientation != UIDeviceOrientationLandscapeLeft || currentOrientation != UIDeviceOrientationLandscapeRight) {
//        [self transformLandscapeLeft];
//    }
    
    UIInterfaceOrientation interfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    if (interfaceOrientation == UIInterfaceOrientationPortrait || interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        [self transformLandscapeLeft];
    }

}



- (void)transformPortrait {
    
    isFullScreen = NO;
    deviceOrientation = DeviceOrientationPortrait;
    
    [UIView animateWithDuration:0.5 animations:^{
        self.view.transform = CGAffineTransformRotate(CGAffineTransformIdentity, 0);
        //    self.view.transform = CGAffineTransformRotate(CGAffineTransformIdentity, 0);
        
        self.view.bounds = CGRectMake(0, 0, WIDTH, HEIGHT);
        self.view.center = CGPointMake(WIDTH/2, HEIGHT/2);
        
        [self transformMonitorPortrait];
        [self transformTopToolBarPortrait];
        [self transformBottomToolBarPortrait];
        [self transformMirrorPortrait];
        [self transformZoomfocusPortrait];
        [self transformPresetPortrait];
        [self transformMicrophonePortrait];
        [self transformRecordingPortrait];
        [self transformQualityPortrait];
        [self transformLightViewPortrait];
        
    }];
}

- (void)transformLandscapeLeft {
    
    isFullScreen = YES;
    deviceOrientation = DeviceOrientationLandscapeLeft;

    [UIView animateWithDuration:0.5 animations:^{
        self.view.transform = CGAffineTransformRotate(CGAffineTransformIdentity, M_PI_2);
        self.view.bounds = CGRectMake(0, 0, HEIGHT, WIDTH);
        self.view.center = CGPointMake(WIDTH/2, HEIGHT/2);
        
        [self transformMonitorLandscapeLeft];
        [self transformTopToolBarLandscapeLeft];
        [self transformBottomToolBarLandscapeLeft];
        [self transformMirrorLandscapeLeft];
        [self transformZoomfocusLandscapeLeft];
        [self transformPresetLandscapeLeft];
        [self transformMicrophoneLandscapeLeft];
        [self transformRecordingLandscapeLeft];
        [self transformQualityLandscapeLeft];
        [self transformLightViewLandscapeLeft];

    }];
}

- (void)transformLandscapeRight {
    
    isFullScreen = YES;
    deviceOrientation = DeviceOrientationLandscapeRight;

}



#pragma mark - UIScrollViewDelegate
//返回缩放对象
-(UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{
    if (scrollView.tag == SMONITOR) {
        return self.monitor;
    }
    return nil;
}


//实现对象在缩放过程中居中
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    
    //    NSLog(@">>>zoomScalec:%f", _smonitor.zoomScale);
    //    NSLog(@"s(%2f %2f %2f %2f)", scrollView.frame.origin.x, scrollView.frame.origin.y, scrollView.frame.size.width, scrollView.frame.size.height);
    //    NSLog(@"m(%2f %2f %2f %2f)", _monitor.frame.origin.x, _monitor.frame.origin.y, _monitor.frame.size.width, _monitor.frame.size.height);
    //    NSLog(@"s(%2f %2f)", scrollView.center.x, scrollView.center.y);
    //    NSLog(@"m(%2f %2f)", scrollView.center.x, scrollView.center.y);
    
    if (scrollView.tag == SMONITOR) {
        
        scrollView.zoomScale = scrollView.zoomScale <= 1 ? 1.0f :scrollView.zoomScale;
        
        CGFloat xcenter = scrollView.center.x , ycenter = scrollView.center.y;
        
        xcenter = scrollView.contentSize.width > scrollView.frame.size.width ? scrollView.contentSize.width/2 : xcenter;
        
        ycenter = scrollView.contentSize.height > scrollView.frame.size.height ? scrollView.contentSize.height/2 : ycenter;
        
        self.monitor.center = CGPointMake(xcenter, ycenter);
    }
}

- (void)setupMonitor:(BOOL)fullScreen {
    
    [self.view addSubview:self.smonitor];
    //[self transfromMonitorLandscapeLeft];
    [self addGestureRecognizer];

}


- (UIScrollView *)smonitor {
    if (!_smonitor) {
        
        _smonitor = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, WIDTH, HEIGHT)];
        
        //_smonitor.backgroundColor = [UIColor blueColor];
        _smonitor.delegate = self;
        _smonitor.bounces = NO;
        _smonitor.multipleTouchEnabled = YES;
        _smonitor.minimumZoomScale = 1.0;
        _smonitor.maximumZoomScale = 10.0;
        _smonitor.showsVerticalScrollIndicator = NO;
        _smonitor.showsHorizontalScrollIndicator = NO;
        _smonitor.tag = SMONITOR;
        _smonitor.userInteractionEnabled = YES;

        [_smonitor addSubview:self.monitor];
    }
    return _smonitor;
}

//视频渲染器
- (HiGLMonitor *)monitor {
    if (!_monitor) {
        
        CGFloat h = WIDTH/1.5;
        
        UIInterfaceOrientation interfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
        
        
        if (interfaceOrientation == UIInterfaceOrientationLandscapeLeft || interfaceOrientation == UIInterfaceOrientationLandscapeRight) {
            h = HEIGHT;
        }

        _monitor = [[HiGLMonitor alloc] initWithFrame:CGRectMake(0, 0, WIDTH, h)];
        _monitor.center = self.view.center;
        [self.camera startLiveShow:0 Monitor:_monitor];
    }
    return _monitor;
}

- (void)transformMonitorPortrait {
    
    CGRect monitorBounds = CGRectMake(0, 0, WIDTH, HEIGHT);
    
    self.smonitor.zoomScale = 1.0f;
    self.smonitor.frame = monitorBounds;
    self.smonitor.contentSize = CGSizeMake(WIDTH, HEIGHT);
    
    self.monitor.bounds = CGRectMake(0, 0, WIDTH, WIDTH/1.5);
    self.monitor.center = CGPointMake(WIDTH/2, HEIGHT/2);
}

- (void)transformMonitorLandscapeLeft {
    
    CGRect monitorBounds = CGRectMake(0, 0, HEIGHT, WIDTH);
//    CGRect monitorBounds = CGRectMake(0, 0, 157, 104);

    self.smonitor.zoomScale = 1.0f;
    self.smonitor.frame = monitorBounds;
    //_smonitor.center = CGPointMake(HEIGHT/2, WIDTH/2);
    self.smonitor.contentSize = CGSizeMake(HEIGHT, WIDTH);
    
    self.monitor.frame = monitorBounds;
}



#pragma mark -- 添加手势
- (void)addGestureRecognizer {
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [self.monitor addGestureRecognizer:tap];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.monitor addGestureRecognizer:pan];
}

- (void)tap:(UIGestureRecognizer *)recognizer {
    
    //隐藏工具栏
    self.topToolBar.isUp ? [self.topToolBar moveDown] : [self.topToolBar moveUp];
    self.bottomToolBar.isUp ? [self.bottomToolBar moveUp] : [self.bottomToolBar moveDown];
    
    [self dismissAll];
}


- (void)pan:(UIPanGestureRecognizer *)recognizer {
    
    UIView *view = recognizer.view;
    
    if(view.bounds.size.width - view.frame.size.width == 0)
    {
        
        CGPoint translation = [recognizer translationInView:view.superview];
        
        
        if (recognizer.state == UIGestureRecognizerStateBegan )
        {
            
            //direction = kCameraMoveDirectionNone;
            NSLog(@"x:%f    y:%f",translation.x,translation.y);
            
        }
        else if (recognizer.state == UIGestureRecognizerStateEnded )
        {
            //命令发送间隔为500ms
            double new_time = ((double)[[NSDate date] timeIntervalSince1970])*1000.0;
            BOOL isCtrl = NO;
            
            if (new_time - ptz_ctrl_time > 500 ) {
                isCtrl = YES;
                ptz_ctrl_time = new_time;
            }
            
            if (isCtrl) {
                NSInteger directon = [self.camera direction:translation];
                [self.camera moveDirection:directon runMode:HI_P2P_PTZ_MODE_STEP];
            }
            
        }
        
    }//@if
}


#pragma mark - 屏幕旋转(暂时未使用该系列方法)
//- (BOOL)shouldAutorotate {
//    return YES;
//}

//- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
//    return UIInterfaceOrientationMaskAllButUpsideDown;
//}

//切换横竖屏
//- (void)forceChangeToOrientation:(UIInterfaceOrientation)interfaceOrientation {
//    [[UIDevice currentDevice] setValue:[NSNumber numberWithInteger:interfaceOrientation] forKey:@"orientation"];
//}
//
//- (void)statusBarOrientationsDidChange:(NSNotification *)notification {
//    
//    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
//
//    if (orientation == UIInterfaceOrientationPortrait) {
//        isFullScreen = NO;
//    }
//    
//    if (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) {
//        isFullScreen = YES;
//    }
//    
//    [self setupMonitor:isFullScreen];
//    [self setupTopToolBar:isFullScreen];
//    [self setupBottomToolBar:isFullScreen];
//
//}


#pragma mark - ToolBarDelegate

- (void)toolBar:(NSInteger)barTag didSelectedAtIndex:(NSInteger)index selected:(BOOL)select {
    
    if (barTag == 0) {
        
        // 改变工具栏按钮的选中状态
        [self.topLiveModels enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            if ([self.camera getCommandFunction:HI_P2P_WHITE_LIGHT_GET]) {
                
                LiveModel *t_live = (LiveModel *)obj;
                if (![t_live.normalImgName isEqualToString:@"light_gray"] || index != idx) {
                    [self.topToolBar setSelect:NO atIndex:(int)idx];
                }
            }
            else {
                if (index != idx) {
                    [self.topToolBar setSelect:NO atIndex:(int)idx];
                }
            }
            
        }];// @enumerateObjectsUsingBlock
        
        LiveModel *t_livem = self.topLiveModels[index];
        
        if (select) {
            [self performSelector:t_livem.selectSelector withObject:nil afterDelay:0];
        }
        else {
            [self performSelector:t_livem.normalSelector withObject:nil afterDelay:0];
        }
        
    }// @barTag == 0
    
    
    if (barTag == 1) {
        
        LiveModel *t_livem = self.bottomLiveModels[index];
        
        if (select) {
            [self performSelector:t_livem.selectSelector withObject:nil afterDelay:0];
        }
        else {
            [self performSelector:t_livem.normalSelector withObject:nil afterDelay:0];
        }

    }// @barTag == 1
}

//- (void)didClickTag:(NSInteger)tag atIndex:(NSInteger)index {
//    
//    
//    if (tag == 0) {
//        
//        if (index == 0) {
//            [self showMirror];
//        }
//        
//        if (index == 1) {
//            [self showZoomFocus];
//        }
//
//        if (index == 2) {
//            [self showPreset];
//        }
//        
//        if (index == 3) {
//            [self exit];
//        }
//        
//    }
//    
//    
//    if (tag == 1) {
//        
//        if (index == 0) {
//            [self showMicrophone];
//        }
//        
//        if (index == 1) {
//            [self takeSnapShot];
//        }
//        
//        if (index == 2) {
//            [self takeRecording];
//        }
//        
//        
//        if (index == 3) {
//            [self showQuality];
//        }
//        
//        if (index == 4) {
//            isFullScreen ? [self transformPortrait] : [self transformLandscapeLeft];
//        }
//    }
//}


- (void)dismissAll {
    //隐藏镜像翻转
    self.mirror.isShow ? [self.mirror dismiss]: nil;
    //隐藏变焦
    self.zoomfocus.isShow ? [self.zoomfocus dismiss] : nil;
    //隐藏预置位
    self.preset.isShow ? [self.preset dismiss] : nil;
    
    //隐藏高清流畅切换
    !self.quality.isShow ? [self.quality show] : nil ;

    self.lightView.isShow ? [self.lightView dismiss] : nil ;
    
    
    [self.topLiveModels enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        if ([self.camera getCommandFunction:HI_P2P_WHITE_LIGHT_GET]) {
            
            LiveModel *t_live = (LiveModel *)obj;
            if (![t_live.normalImgName isEqualToString:@"light_gray"]) {
                [self.topToolBar setSelect:NO atIndex:(int)idx];
            }
            
        }
        else {
            [self.topToolBar setSelect:NO atIndex:(int)idx];
        }
        
    }];// @enumerateObjectsUsingBlock
}


#pragma mark - topToolBar/顶部工具栏
- (void)setupTopToolBar:(BOOL)fullScreen {
    
    [self.view addSubview:self.topToolBar];
}

- (NSMutableArray *)topLiveModels {
    if (!_topLiveModels) {
        _topLiveModels = [[NSMutableArray alloc] initWithCapacity:0];
        
        
        // 镜像／翻转
        if ([self.camera getCommandFunction:HI_P2P_SET_DISPLAY_PARAM]) {
            [_topLiveModels addObject:[LiveModel modelWithNormalImage:@"mirror_white" selectImage:@"mirror_white" normalSel:@selector(showMirror) selectSel:@selector(showMirror)]];
        }
        
        
        // 数字变焦
        if ([self.camera getCommandFunction:HI_P2P_SET_PTZ_CTRL]) {
            [_topLiveModels addObject:[LiveModel modelWithNormalImage:@"zoom_focus" selectImage:@"zoom_focus" normalSel:@selector(showZoomFocus) selectSel:@selector(showZoomFocus)]];
        }
        
        
        // 预置位调用
        if ([self.camera getCommandFunction:HI_P2P_SET_PTZ_PRESET]) {
            [_topLiveModels addObject:[LiveModel modelWithNormalImage:@"mark" selectImage:@"mark" normalSel:@selector(showPreset) selectSel:@selector(showPreset)]];
        }
        
        
        // 军／警视卫版本才有白光灯
        if ([DisplayName isEqualToString:@"JS-AP131"] || [DisplayName isEqualToString:@"KS-AP130"]) {
            
            // 白光灯／夜视模式
            // 如果有   HI_P2P_WHITE_LIGHT_GET_EXT 则为夜视选项模式
            // 如果没有 HI_P2P_WHITE_LIGHT_GET_EXT 则判断 HI_P2P_WHITE_LIGHT_GET
            // 如果有   HI_P2P_WHITE_LIGHT_GET 则为白光灯开关模式
            // 如果没有 HI_P2P_WHITE_LIGHT_GET 则不需要显示
            if ([self.camera getCommandFunction:HI_P2P_WHITE_LIGHT_GET_EXT]) {
                LOG(@"live_topbar_getCommandFunction 夜视选择模式");
                [_topLiveModels addObject:[LiveModel modelWithNormalImage:@"light_gray" selectImage:@"light_blue" normalSel:@selector(showLightView) selectSel:@selector(showLightView)]];
                [self.camera request:HI_P2P_WHITE_LIGHT_GET_EXT dson:nil];
            }
            else {
                if ([self.camera getCommandFunction:HI_P2P_WHITE_LIGHT_GET]) {
                    LOG(@"live_topbar_getCommandFunction 白光灯开关模式");
                    [_topLiveModels addObject:[LiveModel modelWithNormalImage:@"light_gray" selectImage:@"light_blue" normalSel:@selector(turnOffWhiteLight) selectSel:@selector(turnOnWhiteLight)]];
                    [self.camera request:HI_P2P_WHITE_LIGHT_GET dson:nil];
                }
            }

        }// @isEqualToString
        
        
        
        
        // 退出
        [_topLiveModels addObject:[LiveModel modelWithNormalImage:@"exitbutton" selectImage:@"exitbutton" normalSel:@selector(exit) selectSel:@selector(exit)]];
        
        
    }
    return _topLiveModels;
}



- (ToolBar *)topToolBar {
    if (!_topToolBar) {
        
        CGFloat h = 40.0f;
        //int num = 4;
        
        _topToolBar = [[ToolBar alloc] initWithFrame:CGRectMake(0, 0, WIDTH, h) btnNumber:(int)self.topLiveModels.count];
        _topToolBar.tag = 0;
        _topToolBar.delegate = self;
        
//        NSArray *images = @[[UIImage imageNamed:@"mirror_white"], [UIImage imageNamed:@"zoom_focus"],
//                            [UIImage imageNamed:@"mark"], [UIImage imageNamed:@"exitbutton"]];
//        
//        for (int i = 0; i < num; i++) {
//            [_topToolBar setImage:images[i] atIndex:i forState:UIControlStateNormal];
//        }
        
        
        for (int i = 0; i < self.topLiveModels.count; i++) {
            
            LiveModel *t_livem = self.topLiveModels[i];
            //NSLog(@"normalImgName : %@", t_livem.normalImgName);
            [_topToolBar setImage:[UIImage imageNamed:t_livem.normalImgName] atIndex:i forState:UIControlStateNormal];
            [_topToolBar setImage:[UIImage imageNamed:t_livem.selectImgName] atIndex:i forState:UIControlStateSelected];
            
//            UIImage *imgs = [UIImage imageWithColor:RGBA_COLOR(100, 0, 0, 1) wihtSize:CGSizeMake(100, 100)];
//            UIImage *imgn = [UIImage imageWithColor:RGBA_COLOR(0, 0, 100, 1) wihtSize:CGSizeMake(100, 100)];
//            
//            [_topToolBar setBackgroudImage:imgn atIndex:i forState:UIControlStateNormal];
//            [_topToolBar setBackgroudImage:imgs atIndex:i forState:UIControlStateSelected];

        }// @for
    }
    return _topToolBar;
}

- (void)transformTopToolBarPortrait {
    
    CGFloat h = self.topToolBar.frame.size.height;
    self.topToolBar.frame = CGRectMake(0, 0, WIDTH, h);
    [self.topToolBar setNeedsDisplay];
}

- (void)transformTopToolBarLandscapeLeft {
    
    CGFloat h = self.topToolBar.frame.size.height;
    self.topToolBar.frame = CGRectMake(0, 0, HEIGHT, h);
    [self.topToolBar setNeedsDisplay];
}


#pragma mark --- MirrorView/镜像与翻转
- (MirrorView *)mirror {
    if (!_mirror) {
        
        CGFloat y = CGRectGetMaxY(self.topToolBar.frame)+20;
        _mirror = [[MirrorView alloc] initWithFrame:CGRectMake(-2*MirrorW, y, MirrorW, MirrorH)];
        //_mirror.switchMirror.on = _display.u32Mirror == 1 ? YES : NO;
        //_mirror.switchFlip.on = _display.u32Flip == 1 ? YES : NO;
        
        __weak typeof(self) weakSelf = self;
        
        _mirror.mirrorBlock = ^(SwitchTag tag, UISwitch *tswitch) {
          
            if (tag == SwitchTagMirror) {
                weakSelf.display.u32Mirror = tswitch.on ? 1 : 0;
            }
            
            if (tag == SwitchTagFlip) {
                weakSelf.display.u32Flip = tswitch.on ? 1 : 0;
            }
            
            [weakSelf.camera request:HI_P2P_SET_DISPLAY_PARAM dson:[weakSelf.camera dic:weakSelf.display]];
            
        };
    }
    return _mirror;
}

- (void)transformMirrorPortrait {
    self.mirror.isShow ? [self.mirror dismiss] : nil;
    CGFloat y = CGRectGetMaxY(self.topToolBar.frame)+20;
    self.mirror.frame = CGRectMake(-2*MirrorW, y, MirrorW, MirrorH);
}

- (void)transformMirrorLandscapeLeft {
    self.mirror.isShow ? [self.mirror dismiss] : nil;
    CGFloat y = CGRectGetMaxY(self.topToolBar.frame)+20;
    self.mirror.frame = CGRectMake(-2*MirrorW, y, MirrorW, MirrorH);
}

- (void)showMirror {
    
    //隐藏变焦
    self.zoomfocus.isShow ? [self.zoomfocus dismiss] : nil;
    //隐藏预置位
    self.preset.isShow ? [self.preset dismiss] : nil;
    //
    self.lightView.isShow ? [self.lightView dismiss] : nil ;
    
    self.mirror.isShow ? [self.mirror dismiss] : [self.mirror show];
    
}

- (void)dismissMirror {
    self.mirror.isShow ? [self.mirror dismiss] : nil;
}




#pragma mark -- ZoomFocusDialog/变焦
- (ZoomFocusDialog *)zoomfocus {
    if (!_zoomfocus) {
        
        _zoomfocus = [[ZoomFocusDialog alloc] initWithFrame:CGRectMake(0, 0, ZoomW, ZoomH)];
        _zoomfocus.center = CGPointMake(WIDTH/2, -ZoomH-ZoomH/2);
        
        __weak typeof(self) weakSelf = self;
        
        _zoomfocus.zoomBlock = ^(NSInteger tag, NSInteger type) {
          
            if (type == ZOOMFOCUS_BTN_DOWN) {
             
                if (tag == 0) {
                    [weakSelf.camera zoomWithCtrl:HI_P2P_PTZ_CTRL_ZOOMIN];
                }
                
                if (tag == 1) {
                    [weakSelf.camera zoomWithCtrl:HI_P2P_PTZ_CTRL_ZOOMOUT];
                }

                if (tag == 2) {
                    [weakSelf.camera zoomWithCtrl:HI_P2P_PTZ_CTRL_FOCUSIN];
                }

                if (tag == 3) {
                    [weakSelf.camera zoomWithCtrl:HI_P2P_PTZ_CTRL_FOCUSOUT];
                }
            }
            
            if (type == ZOOMFOCUS_BTN_UP) {
                
                [weakSelf.camera zoomWithCtrl:HI_P2P_PTZ_CTRL_STOP];
            }

        };// @zoomBlock
        
    }
    return _zoomfocus;
}


- (void)transformZoomfocusPortrait {
    self.zoomfocus.isShow ? [self.zoomfocus show] : nil;
    self.zoomfocus.center = CGPointMake(WIDTH/2, -ZoomH/2-ZoomH);
}

- (void)transformZoomfocusLandscapeLeft {
    self.zoomfocus.isShow ? [self.zoomfocus show] : nil;
    self.zoomfocus.center = CGPointMake(HEIGHT/2, -ZoomH/2-ZoomH);
}

- (void)showZoomFocus {
    
    //隐藏镜像翻转
    self.mirror.isShow ? [self.mirror dismiss]: nil;
    //隐藏预置位
    self.preset.isShow ? [self.preset dismiss] : nil;
    
    self.lightView.isShow ? [self.lightView dismiss] : nil;
    
    self.zoomfocus.isShow ? [self.zoomfocus dismiss] : [self.zoomfocus show];
    
}

- (void)dismissZoomFocus {
    self.zoomfocus.isShow ? [self.zoomfocus dismiss] : nil;
}


#pragma mark -- PresetDialog/预置位
- (PresetDialog *)preset {
    if (!_preset) {
        
        _preset = [[PresetDialog alloc] initWithFrame:CGRectMake(0, 0, PresetW, PresetH)];
        _preset.center = CGPointMake(WIDTH/2, -PresetH-PresetH/2);
        
        __weak typeof(self) weakSelf = self;
        
        _preset.presetBlock = ^(NSInteger index, PresetType type) {
            
            if (type == PresetTypeCall) {
                [weakSelf.camera presetWithNumber:index action:HI_P2P_PTZ_PRESET_ACT_CALL];
            }
            
            if(type == PresetTypeSet) {
                [weakSelf.camera presetWithNumber:index action:HI_P2P_PTZ_PRESET_ACT_SET];
            }
        };

    }
    return _preset;
}


- (void)transformPresetPortrait {
    self.preset.isShow ? [self.preset show] : nil;
    self.preset.center = CGPointMake(WIDTH/2, -PresetH/2-PresetH);
}

- (void)transformPresetLandscapeLeft {
    self.preset.isShow ? [self.preset show] : nil;
    self.preset.center = CGPointMake(HEIGHT/2, -PresetH/2-PresetH);
}

- (void)showPreset {
    //隐藏镜像翻转
    self.mirror.isShow ? [self.mirror dismiss]: nil;
    //隐藏变焦
    self.zoomfocus.isShow ? [self.zoomfocus dismiss] : nil;
    self.lightView.isShow ? [self.lightView dismiss] : nil;
    self.preset.isShow ? [self.preset dismiss] : [self.preset show];
    
}

- (void)dismissPreset {
    self.preset.isShow ? [self.preset dismiss] : nil;
}


#pragma mark -- 白光灯
- (WhiteLightView *)lightView {
    if (!_lightView) {
        
        CGFloat w = 200.0f;
        CGFloat h = 120.0f;
        CGFloat px = [UIScreen mainScreen].bounds.size.height/2;
        //CGFloat py = [UIScreen mainScreen].bounds.size.width/2;
        
        _lightView = [[WhiteLightView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
        _lightView.center = CGPointMake(px, -h);
        _lightView.camera = self.camera;
        
    }
    return _lightView;
}

- (void)showLightView {
    
    //隐藏变焦
    self.zoomfocus.isShow ? [self.zoomfocus dismiss] : nil;
    //隐藏预置位
    self.preset.isShow ? [self.preset dismiss] : nil;
    
    self.mirror.isShow ? [self.mirror dismiss] : nil;
    
    self.lightView.isShow ? [self.lightView dismiss] : [self.lightView show];
    
}

- (void)transformLightViewPortrait {
    self.lightView.isShow ? [self.lightView show] : nil;
    self.lightView.center = CGPointMake(WIDTH/2, -CGRectGetHeight(self.lightView.frame));
}

- (void)transformLightViewLandscapeLeft {
    self.lightView.isShow ? [self.lightView show] : nil;
    self.lightView.center = CGPointMake(HEIGHT/2, -CGRectGetHeight(self.lightView.frame));
}

- (void)turnOnCameraWhiteLight {
    [self.camera turnOnWhiteLight];
}

- (void)turnOffCameraWhiteLight {
    [self.camera turnOffWhiteLight];
}


#pragma mark -- 退出
- (void)exit {
    
    if (self.mirror) {
        [self.mirror removeFromSuperview];
    }
    
    
    //Goke版本的摄像机每次退出实时界面时更换显示画面
    if ([self.camera isGoke]) {
        if (self.isShowing) {
            [self.camera saveImage:[self.camera getSnapshot]];
        }
    }
    
    
    [self.camera stopLiveShow];
    
    // 延时0.5s后推送，确保所有线程关闭完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
    
}


#pragma mark - bottomToolBar／底部工具栏
- (void)setupBottomToolBar:(BOOL)fullScreen {
    [self.view addSubview:self.bottomToolBar];
}

- (NSMutableArray *)bottomLiveModels {
    if (!_bottomLiveModels) {
        
        _bottomLiveModels = [[NSMutableArray alloc] initWithCapacity:0];
        
        // 对讲／监听
        [_bottomLiveModels addObject:[LiveModel modelWithNormalImage:@"speaker_on" selectImage:@"speaker_off" normalSel:@selector(showMicrophone) selectSel:@selector(showMicrophone)]];
        
        // 快照
        [_bottomLiveModels addObject:[LiveModel modelWithNormalImage:@"snopshot" selectImage:@"snopshot" normalSel:@selector(takeSnapShot) selectSel:@selector(takeSnapShot)]];
        
        // 录像
        [_bottomLiveModels addObject:[LiveModel modelWithNormalImage:@"record_white" selectImage:@"record_red" normalSel:@selector(takeRecording) selectSel:@selector(takeRecording)]];
        
        // 流畅／高清
        [_bottomLiveModels addObject:[LiveModel modelWithNormalImage:@"share" selectImage:@"share" normalSel:@selector(showQuality) selectSel:@selector(showQuality)]];
        
        // 全屏
//        [_bottomLiveModels addObject:[LiveModel modelWithNormalImage:@"share" selectImage:@"share" normalSel:@selector(transformPortrait) selectSel:@selector(transformLandscapeLeft)]];
        
    }
    return _bottomLiveModels;
}


- (ToolBar *)bottomToolBar {
    if (!_bottomToolBar) {
        
        CGFloat h = 40.0f;
        CGFloat y = HEIGHT - h;

        //int num = 4;
        
        _bottomToolBar = [[ToolBar alloc] initWithFrame:CGRectMake(0, y, WIDTH, h) btnNumber:(int)self.bottomLiveModels.count];
        _bottomToolBar.tag = 1;
        _bottomToolBar.delegate = self;
        //    self.bottomToolBar.frame = CGRectMake(x, y, w, h);
        
//        [_bottomToolBar setImage:[UIImage imageNamed:@"speaker_on"] atIndex:0 forState:UIControlStateNormal];
//        [_bottomToolBar setImage:[UIImage imageNamed:@"speaker_off"] atIndex:0 forState:UIControlStateSelected];
//        [_bottomToolBar setImage:[UIImage imageNamed:@"snopshot"] atIndex:1 forState:UIControlStateNormal];
//        [_bottomToolBar setImage:[UIImage imageNamed:@"record_white"] atIndex:2 forState:UIControlStateNormal];
//        [_bottomToolBar setImage:[UIImage imageNamed:@"record_red"] atIndex:2 forState:UIControlStateSelected];
//        [_bottomToolBar setImage:[UIImage imageNamed:@"share"] atIndex:3 forState:UIControlStateNormal];
//        [_bottomToolBar setTitle:@"Full" atIndex:4 forState:UIControlStateNormal];
        
        
        
        for (int i = 0; i < self.bottomLiveModels.count; i++) {
            
            LiveModel *t_livem = self.bottomLiveModels[i];
            
            [_bottomToolBar setImage:[UIImage imageNamed:t_livem.normalImgName] atIndex:i forState:UIControlStateNormal];
            [_bottomToolBar setImage:[UIImage imageNamed:t_livem.selectImgName] atIndex:i forState:UIControlStateSelected];
        
        }// @for
        
    }
    return _bottomToolBar;
}

- (void)transformBottomToolBarPortrait {
    CGFloat h = self.bottomToolBar.frame.size.height;
    CGFloat y = HEIGHT-h;
    self.bottomToolBar.frame = CGRectMake(0, y, WIDTH, h);
    [self.bottomToolBar setNeedsDisplay];
}

- (void)transformBottomToolBarLandscapeLeft {
    CGFloat h = self.bottomToolBar.frame.size.height;
    CGFloat y = WIDTH-h;
    self.bottomToolBar.frame = CGRectMake(0, y, HEIGHT, h);
    [self.bottomToolBar setNeedsDisplay];
}


#pragma mark -- Microphone/麦克风按钮
- (Microphone *)microphone {
    
    if (!_microphone) {
        
        CGFloat px = WIDTH+MicrophoneH/2+MicrophoneH;
        CGFloat py = HEIGHT-MicrophoneH/2-40;
        
        _microphone = [[Microphone alloc] initWithFrame:CGRectMake(0, 0, MicrophoneH, MicrophoneH)];
        _microphone.center = CGPointMake(px, py);
        
        __weak typeof(self) weakSelf = self;
        _microphone.microphoneBlock = ^(PressType type) {
            
            if (type == PressTypeDown) {
                
                [weakSelf.camera stopListening];
                [weakSelf.camera startTalk];

            }
            
            if (type == PressTypeUpInside) {
               
                [weakSelf.camera stopTalk];
                [weakSelf.camera startListening];
            }

        };
    }
    
    return _microphone;
}

- (void)transformMicrophonePortrait {
//    self.microphone.isShow ? [self.microphone dismiss] : nil;
//    self.microphone.center = CGPointMake(WIDTH+MicrophoneH/2+MicrophoneH, HEIGHT-MicrophoneH/2-40);
    
    if (self.microphone.isShow) {
        self.microphone.center = CGPointMake(WIDTH-MicrophoneH/2, HEIGHT-MicrophoneH/2-40);
    }
    else {
        self.microphone.center = CGPointMake(WIDTH+MicrophoneH/2+MicrophoneH, HEIGHT-MicrophoneH/2-40);
    }
}

- (void)transformMicrophoneLandscapeLeft {
//    self.microphone.isShow ? [self.microphone dismiss] : nil;
//    self.microphone.center = CGPointMake(HEIGHT+MicrophoneH/2+MicrophoneH, WIDTH-MicrophoneH/2-40);
    
    if (self.microphone.isShow) {
        self.microphone.center = CGPointMake(HEIGHT-MicrophoneH/2, WIDTH-MicrophoneH/2-40);
    }
    else {
        self.microphone.center = CGPointMake(HEIGHT+MicrophoneH/2+MicrophoneH, WIDTH-MicrophoneH/2-40);
    }
}

- (void)showMicrophone {
    
    [self dismissAll];
    
    if (self.microphone.isShow) {
        
        [self.camera stopTalk];
        [self.camera stopListening];
        
        [self.microphone dismiss];
    }
    else {
        
        [self.camera startListening];
        [self.camera stopTalk];
        
        [self.microphone show];
    }

}



#pragma mark -- 截图
- (void)takeSnapShot {
    
    
    BOOL success = [GBase savePictureForCamera:self.camera];
    if (success) {
        
        //NSMutableArray *pictures = [GBase picturesForCamera:self.camera];
        //LOG(@"pictures.count:%ld", pictures.count)
        
        [self presentMessage:INTERSTR(@"Snapshot Saved") atDeviceOrientation:deviceOrientation];
    }
    else {
        
    }
}

- (void)presentMessage:(NSString *)message atDeviceOrientation:(DeviceOrientation)orientation {
    
    if (orientation == DeviceOrientationPortrait) {
        [[iToast makeText:message] show];
    }
    
    if (orientation == DeviceOrientationLandscapeLeft) {
        [[iToast makeText:message] showRota];
    }
    
    if (orientation == DeviceOrientationLandscapeRight) {
        [[iToast makeText:message] showUnRota];
    }
}

#pragma mark -- 录像
- (void)takeRecording {
    //self.record.isShow ? [self.record dismiss] : [self.record show];

    if (self.record.isShow) {
        
        [self.record dismiss];
        
        [self.camera stopRecording];
        
        //NSMutableArray *recordings = [GBase recordingsForCamera:self.camera];
        //LOG(@"recordings.count:%ld", recordings.count)

    }
    else {
        
        [self.record show];
        
        [GBase saveRecordingForCamera:self.camera];
    }

}


#pragma mark -- Recording/录像
- (Recording *)record {
    if (!_record) {
        
        CGFloat px = CGRectGetMaxX(self.monitor.frame)-50;
        CGFloat py = CGRectGetMinY(self.monitor.frame)+30;
        
        _record = [[Recording alloc] initWithFrame:CGRectMake(0, 0, RecordingW, RecordingH)];
        _record.center = CGPointMake(px, py);
    }
    return _record;
}

- (void)transformRecordingPortrait {
    CGFloat px = CGRectGetMaxX(self.monitor.frame)-50;
    CGFloat py = CGRectGetMinY(self.monitor.frame)+30;
    
    self.record.center = CGPointMake(px, py);
}

- (void)transformRecordingLandscapeLeft {
    CGFloat px = CGRectGetMaxX(self.monitor.frame)-50;
    CGFloat py = CGRectGetMinY(self.monitor.frame)+60;
    
    self.record.center = CGPointMake(px, py);
}


#pragma mark -- QualityDialog
- (QualityDialog *)quality {
    if (!_quality) {
        _quality = [[QualityDialog alloc] initWithFrame:CGRectMake(0, 0, QualityW, QualityH)];
        CGFloat px = WIDTH+QualityW/2+QualityW;
        CGFloat py = HEIGHT-QualityH/2-60;
        _quality.center = CGPointMake(px, py);
        _quality.btnHigh.selected = YES;//默认第一码流
        
        __weak typeof(self) weakSelf = self;
        
        _quality.qualityBlock = ^(QualityType type) {
          
            [HXProgress showProgress];
            
            if (type == QualityTypeHigh) {
                
                qualityType = QualityTypeHigh;
                
                [weakSelf.camera stopLiveShow];
                [weakSelf.camera disconnect];
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [weakSelf.camera connect];
                });

            }
            
            if (type == QualityTypeLow) {
             
                qualityType = QualityTypeLow;
                
                [weakSelf.camera stopLiveShow];
                [weakSelf.camera disconnect];
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [weakSelf.camera connect];
                });
                
            }

        };// @qualityBlock
        
    }
    return _quality;
}

- (void)transformQualityPortrait {
    !self.quality.isShow ? [self.quality dismiss] : nil ;
    
    CGFloat px = WIDTH+QualityW/2+QualityW;
    CGFloat py = HEIGHT-QualityH/2-60;
    
    self.quality.center = CGPointMake(px, py);
}

- (void)transformQualityLandscapeLeft {
    !self.quality.isShow ? [self.quality dismiss] : nil ;

    CGFloat px = HEIGHT+QualityW/2+QualityW;
    CGFloat py = WIDTH-QualityH/2-60;
    
    self.quality.center = CGPointMake(px, py);
}

- (void)showQuality {
    
    if (self.microphone.isShow) {
        [self presentMessage:INTERSTR(@"Can't change quality while Speaking") atDeviceOrientation:deviceOrientation];
        return;
    }
    
    self.quality.isShow ? [self.quality dismiss] : [self.quality show];
}


/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
