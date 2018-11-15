#import "RNKeyboardHostView.h"

#import <UIKit/UIKit.h>
#import <React/UIView+React.h>
#import <React/RCTAssert.h>
#import <React/RCTRootView.h>
#import <React/RCTShadowView.h>
#import <React/RCTTouchHandler.h>
#import <React/RCTUIManager.h>
#import <React/RCTUtils.h>

#if __has_include(<React/RCTUIManagerUtils.h>)
#import <React/RCTUIManagerUtils.h>
#endif

#import "RNKeyboardContentView.h"
#import "RNKeyboardCoverView.h"
#import "UIViewController+RNKeyboard.h"

@interface RNKeyboardHostView ()

@property (nonatomic, weak) UIView *rootView;

/**
 height of contentView
 */
@property (nonatomic, assign) CGFloat contentHeight;
@property (nonatomic, assign) BOOL contentShown;
@property (nonatomic, assign) BOOL keyboardShown;
@property (nonatomic, assign) BOOL contentOrKeyboardShown;

@end

@implementation RNKeyboardHostView {
    __weak RCTBridge *_bridge;
    __weak RNKeyboardContentView *_contentView;
    __weak RNKeyboardCoverView *_coverView;
    __weak YYKeyboardManager *_manager;
    BOOL _keyboardState;
    BOOL _isPresented;
    BOOL attachedToSuper;
    BOOL _keyboardShownChanged;
    CGFloat _tempPlaceholderHeight;
}

RCT_NOT_IMPLEMENTED(-(instancetype)initWithFrame
                    : (CGRect)frame)
RCT_NOT_IMPLEMENTED(-(instancetype)initWithCoder
                    : coder)

- (instancetype)initWithBridge:(RCTBridge *)bridge {
    if ((self = [super initWithFrame:CGRectZero])) {
        _bridge = bridge;
        _hideWhenKeyboardIsDismissed = YES;
        _contentVisible = YES;
        _manager = [YYKeyboardManager defaultManager];
        [_manager addObserver:self];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(viewControllerWillPresentNotification:)
                                                     name:RNViewControllerWillPresentNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(viewControllerDidDismissNotification:)
                                                     name:RNViewControllerDidDismissNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self
                                                selector:@selector(deviceOrientationDidChange:)
                                                    name:UIDeviceOrientationDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - NSNotification

- (void)viewControllerWillPresentNotification:(NSNotification *)notification {
    if (_contentView && !_keyboardShown && _keyboardPlaceholderHeight > 0) {
        _tempPlaceholderHeight = _keyboardPlaceholderHeight;
        _keyboardPlaceholderHeight = 0;
        [self updateSize];
        [self updateOriginy];
    }
}

- (void)viewControllerDidDismissNotification:(NSNotification *)notification {
    if (_tempPlaceholderHeight) {
        _keyboardPlaceholderHeight = _tempPlaceholderHeight;
        _tempPlaceholderHeight = 0;
        [self updateSize];
        [self updateOriginy];
    }
}

- (void)deviceOrientationDidChange:(NSNotification *) notification {
    [self updateSize];
}

#pragma mark - UIView

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (!self.superview && _isPresented) {
        _isPresented = NO;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!_coverView.superview && self.window) {
        [self autoAddSubview:_coverView onSuperview:self.rootView];
        if (_hideWhenKeyboardIsDismissed && !_manager.keyboardToValid) {
            [_coverView setVisible:NO];
        }
    }
    if (!_contentView.superview && self.window) {
        [self autoAddContentView];
    }

    if (!self.window) {
        [UIView performWithoutAnimation:^() {
            [_manager keyboardWindow].transform = CGAffineTransformIdentity;
        }];
        [_contentView removeFromSuperview];
        [_coverView removeFromSuperview];
        _isPresented = NO;
    }
}

#pragma mark - React

- (void)insertReactSubview:(__kindof UIView *)subview atIndex:(NSInteger)atIndex {
    if ([subview class] == [RNKeyboardContentView class]) {
        RCTAssert(_contentView == nil, @"KeyboardView ContainerView is already existed.");
        subview.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth;
        _contentView = subview;
        [self autoAddContentView];
        [_contentView setVisible:_contentVisible];
    } else if ([subview class] == [RNKeyboardCoverView class]) {
        RCTAssert(_coverView == nil, @"KeyboardView StickyView is already existed.");
        subview.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth;
        _coverView = subview;
        [self autoAddSubview:_coverView onSuperview:self.rootView];
        if (_hideWhenKeyboardIsDismissed && !_manager.keyboardToValid) {
            [_coverView setVisible:NO];
        }
    }

    [UIView performWithoutAnimation:^() {
        [self updateSize];
        [self updateOriginy];
        [super insertReactSubview:subview atIndex:atIndex];
    }];
}

- (void)removeReactSubview:(__kindof UIView *)subview {
    if ([subview class] == [RNKeyboardContentView class]) {
        [_contentView removeFromSuperview];
        _contentView = nil;
        [self autoSetContentOrKeyboardShown];
        [self updateSize];
        [self updateOriginy];
    } else if ([subview class] == [RNKeyboardCoverView class]) {
        [_coverView removeFromSuperview];
        _coverView = nil;
    }
    [super removeReactSubview:subview];
}

- (void)didUpdateReactSubviews {
    // Do nothing, as subviews are managed by `insertReactSubview:atIndex:`
}

- (void)didSetProps:(NSArray<NSString *> *)changedProps {
    if ([changedProps containsObject:@"transform"]) {
        [self synchronousTransform];
    }
}

#pragma mark - RCTInvalidating

- (void)invalidate {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView performWithoutAnimation:^() {
            [_manager keyboardWindow].transform = CGAffineTransformIdentity;
        }];
        [_contentView removeFromSuperview];
        _contentView = nil;
        [_coverView removeFromSuperview];
        _coverView = nil;
        _isPresented = NO;
        [_manager removeObserver:self];
    });
}

#pragma mark - YYKeyboardObserver

- (void)keyboardChangedWithTransition:(YYKeyboardTransition)transition {
    BOOL fromValid = _manager.keyboardFromValid;
    BOOL toValid = _manager.keyboardToValid;

    if (toValid) {
        [self setKeyboardShown:YES];
    }

    _keyboardState = toValid;

    if ((!_manager.inHardwareKeyboardMode &&
         ((!fromValid && toValid && !transition.fromVisible && !transition.toVisible) ||
          (fromValid && !toValid && transition.fromVisible && transition.toVisible))) ||
        (!fromValid && !toValid) || (!_contentView && !_coverView)) {
        return;
    }

    [self autoAddContentView];

    if (!fromValid && !_isPresented) {
        [self synchronousTransform];
    }

    if (toValid) {
        [self updateSize];
        [_coverView setVisible:YES];
        [UIView performWithoutAnimation:^() {
            [_coverView setAlpha:1];
        }];
    }

    // update origin y to the position where keyboard is hidden before animation
    if (!fromValid && !_isPresented) {
        [UIView performWithoutAnimation:^() {
            [self updateOriginyWithKeyboardWillShow:NO];
        }];
        _isPresented = YES;
    }

    [UIView animateWithDuration:transition.animationDuration
        delay:0
        options:transition.animationOption
        animations:^() {
            [self updateOriginy];
            if (!toValid && _hideWhenKeyboardIsDismissed) {
                [_coverView setAlpha:0];
                [_contentView setAlpha:0];
            }
        }
        completion:^(BOOL finished) {
            if (finished && !toValid && !_keyboardState) { // keyboard is not visible
                _isPresented = NO;
                if (_hideWhenKeyboardIsDismissed) {
                    [_coverView setVisible:NO];
                    [_coverView setAlpha:1];
                    [_contentView removeFromSuperview];
                    [_contentView setAlpha:1];
                    [self autoSetContentOrKeyboardShown];
                }
                [self setKeyboardShown:NO];
            }
        }];
}

#pragma mark - Layout

- (void)autoAddContentView {
    [self autoSetContentOrKeyboardShown];
    if (!_contentView) {
        return;
    }
    if ([_manager isKeyboardVisible]) {
        UIWindow *keyboardWindow = [_manager keyboardWindow];
        [self autoAddSubview:_contentView onSuperview:keyboardWindow];
    } else {
        if ([_contentView superview] != self.window && _keyboardPlaceholderHeight > 0) {
            [[_contentView superview] setHidden:YES];
        }
        [self autoAddSubview:_contentView onSuperview:self.window];
    }
}

- (void)updateSize {
    CGSize screenSize = [[UIScreen mainScreen] bounds].size;
    float coverHeight = screenSize.height - self.contentHeight;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self synchronousTransform];
    });

    dispatch_async(RCTGetUIManagerQueue(), ^{
        if (_contentView) {
            RCTShadowView *_contentShadowView = [self getShadowView:_contentView];
            _contentShadowView.size = screenSize;
            // _contentShadowView.yogaNode must not be null
            if (_contentShadowView.yogaNode) {
                YGNodeStyleSetPadding(_contentShadowView.yogaNode, YGEdgeTop, coverHeight);
            }
        }
        if (_coverView) {
            RCTShadowView *_coverShadowView = [self getShadowView:_coverView];
            _coverShadowView.size = CGSizeMake(screenSize.width, coverHeight);
        }
        [_bridge.uiManager setNeedsLayout];
    });
}

- (void)updateOriginy {
    [self updateOriginyWithKeyboardWillShow:_manager.keyboardToValid];
}

- (void)updateOriginyWithKeyboardWillShow:(BOOL)keyboardWillShow {
    float offset = keyboardWillShow ? 0 : (_contentHeight - (_contentView ? _keyboardPlaceholderHeight : 0));
    if (_contentView) {
        CGRect contentFrame = _contentView.frame;
        contentFrame.origin.y = offset;
        [_contentView reactSetFrame:contentFrame];
    }

    if (_coverView) {
        CGRect coverFrame = _coverView.frame;
        coverFrame.origin.y = offset;
        [_coverView reactSetFrame:coverFrame];
    }
}

#pragma mark - Private

- (void)autoSetContentOrKeyboardShown {
    BOOL shown = NO;
    if (_keyboardShown) {
        shown = YES;
    } else if (_contentView && _keyboardPlaceholderHeight > 0) {
        shown = YES;
    }
    [self setContentOrKeyboardShown:shown];
}

- (void)synchronousTransform {
    [UIView performWithoutAnimation:^() {
        if (_manager.keyboardVisible && _synchronouslyUpdateTransform) {
            [_manager keyboardWindow].transform = self.transform;
            _coverView.transform = self.transform;
        }
    }];
}

- (RCTShadowView *)getShadowView:(UIView *)view {
    NSMutableDictionary<NSNumber *, RCTShadowView *> *shadowViewRegistry = [_bridge.uiManager valueForKey:@"shadowViewRegistry"];
    NSNumber *reactTag = view.reactTag;
    return shadowViewRegistry[reactTag];
}

- (void)autoAddSubview:(UIView *)subview onSuperview:(UIView *)superview {
    if (!subview || !superview) {
        return;
    }
    [subview setAlpha:1];
    UIView *originSuperview = [subview superview];
    if (!originSuperview) {
        [superview addSubview:subview];
    } else if (originSuperview != superview) {
        [subview removeFromSuperview];
        [superview addSubview:subview];
    }
}

#pragma mark - Getter

- (UIView *)rootView {
    if (!_rootView) {
        UIView *rootview = self;
        while (![rootview isReactRootView] && rootview != nil) {
            rootview = [rootview superview];
        }
        _rootView = rootview;
    }
    return _rootView;
}

- (CGFloat)contentHeight {
    UIWindow *keyboardWindow = [_manager keyboardWindow];
    if (!keyboardWindow || !_manager.keyboardToValid) { // keyboard is not visible
        CGFloat keyboardPlaceholderHeight = _contentView ? _keyboardPlaceholderHeight : 0;
        _contentHeight = MAX(keyboardPlaceholderHeight, 0);
        return _contentHeight;
    }

    CGRect keyboardFrame = [_manager keyboardFrame];
    CGFloat keyboardHeight = CGRectGetHeight(keyboardFrame);
    CGFloat keyboardWindowHeight = CGRectGetHeight(keyboardWindow.frame);
    CGFloat keyboardVisibleHeight = MAX(keyboardWindowHeight - CGRectGetMinY(keyboardFrame), 0);

    if (keyboardVisibleHeight == 0 || keyboardHeight > keyboardVisibleHeight) { // use external keyboard
        if (_contentView) {
            _contentHeight = _keyboardPlaceholderHeight > 0 ? _keyboardPlaceholderHeight : keyboardHeight;
        } else {
            _contentHeight = 0;
        }
        _contentHeight = MAX(keyboardVisibleHeight, _contentHeight);
    } else {
        _contentHeight = keyboardVisibleHeight > 0 ? keyboardVisibleHeight : (_contentView ? _keyboardPlaceholderHeight : 0);
    }
    return _contentHeight;
}

#pragma mark - Setter

- (void)setHideWhenKeyboardIsDismissed:(BOOL)hideWhenKeyboardIsDismissed {
    if (_hideWhenKeyboardIsDismissed == hideWhenKeyboardIsDismissed) {
        return;
    }

    if (![_manager keyboardToValid]) {
        [_coverView setVisible:!hideWhenKeyboardIsDismissed];
        [self updateSize];
        [self updateOriginy];
    }

    _hideWhenKeyboardIsDismissed = hideWhenKeyboardIsDismissed;
}

- (void)setFullWhenKeyboardDisplay:(BOOL)fullWhenKeyboardDisplay {

}

- (void)setInNative:(BOOL)inNative {

}

- (void)setSynchronouslyUpdateTransform:(BOOL)synchronouslyUpdateTransform {
    if (_synchronouslyUpdateTransform == synchronouslyUpdateTransform) {
        return;
    }

    if (synchronouslyUpdateTransform) {
        [self synchronousTransform];
    }
    _synchronouslyUpdateTransform = synchronouslyUpdateTransform;
}

- (void)setKeyboardPlaceholderHeight:(CGFloat)keyboardPlaceholderHeight {
    if (_keyboardPlaceholderHeight == keyboardPlaceholderHeight) {
        return;
    }
    _keyboardPlaceholderHeight = keyboardPlaceholderHeight;
    [self autoAddContentView];
    [self updateSize];
    [self updateOriginy];
}

- (void)setContentVisible:(BOOL)contentVisible {
    if (_contentVisible == contentVisible) {
        return;
    }
    _contentVisible = contentVisible;
    [_contentView setVisible:contentVisible];
}

- (void)setKeyboardShown:(BOOL)keyboardShown {
    if (_keyboardShown == keyboardShown) {
        return;
    }
    _keyboardShown = keyboardShown;
    _keyboardShownChanged = YES;
    [self autoSetContentOrKeyboardShown];
}

- (void)setContentOrKeyboardShown:(BOOL)contentOrKeyboardShown {
    if (_contentOrKeyboardShown != contentOrKeyboardShown || _keyboardShownChanged) {
        _keyboardShownChanged = NO;
        _contentOrKeyboardShown = contentOrKeyboardShown;
        if (_contentOrKeyboardShown) {
            if (_onKeyboardShow) {
                _onKeyboardShow(@{
                                  @"inHardwareKeyboardMode": @(_manager.inHardwareKeyboardMode),
                                  @"keyboardShown": @(_keyboardShown)
                                  });
            }
        } else {
            if (_onKeyboardHide) {
                _onKeyboardHide(@{
                                  @"keyboardShown": @(_keyboardShown)
                                  });
            }
        }
    }
}

@end
