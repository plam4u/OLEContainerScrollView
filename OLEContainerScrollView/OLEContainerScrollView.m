/*
 OLEContainerScrollView
 
 Copyright (c) 2014 Ole Begemann.
 https://github.com/ole/OLEContainerScrollView
 */

@import QuartzCore;

#import "OLEContainerScrollView.h"

@interface OLEContainerScrollView ()

@property (nonatomic, readonly) NSMutableArray *subviewsInLayoutOrder;

- (void)didAddSubviewToContainer:(UIView *)subview;
- (void)willRemoveSubviewFromContainer:(UIView *)subview;

@end


@interface OLEContainerScrollViewContentView : UIView

@end


@implementation OLEContainerScrollView

static void *KVOContext = &KVOContext;

- (void)dealloc
{
    // Removing the subviews will unregister KVO observers
    for (UIView *subview in self.contentView.subviews) {
        [subview removeFromSuperview];
    }
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInitForOLEContainerScrollView];
    }
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [self commonInitForOLEContainerScrollView];
}

- (void)commonInitForOLEContainerScrollView
{
    _contentView = [[OLEContainerScrollViewContentView alloc] initWithFrame:CGRectZero];
    [self addSubview:_contentView];
    _subviewsInLayoutOrder = [NSMutableArray arrayWithCapacity:4];
}

#pragma mark - Adding and removing subviews

- (void)didAddSubviewToContainer:(UIView *)subview
{
    NSParameterAssert(subview != nil);
    [self.subviewsInLayoutOrder addObject:subview];
    
    if ([subview isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)subview;
        scrollView.scrollEnabled = NO;
        [scrollView addObserver:self forKeyPath:NSStringFromSelector(@selector(contentSize)) options:NSKeyValueObservingOptionOld context:KVOContext];
    } else {
        [subview addObserver:self forKeyPath:NSStringFromSelector(@selector(frame)) options:NSKeyValueObservingOptionOld context:KVOContext];
        [subview addObserver:self forKeyPath:NSStringFromSelector(@selector(bounds)) options:NSKeyValueObservingOptionOld context:KVOContext];
    }
    
    [self setNeedsLayout];
}

- (void)willRemoveSubviewFromContainer:(UIView *)subview
{
    NSParameterAssert(subview != nil);
    
    if ([subview isKindOfClass:[UIScrollView class]]) {
        [subview removeObserver:self forKeyPath:NSStringFromSelector(@selector(contentSize)) context:KVOContext];
    } else {
        [subview removeObserver:self forKeyPath:NSStringFromSelector(@selector(frame)) context:KVOContext];
        [subview removeObserver:self forKeyPath:NSStringFromSelector(@selector(bounds)) context:KVOContext];
    }
    [self.subviewsInLayoutOrder removeObject:subview];
    [self setNeedsLayout];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == KVOContext) {
        // Initiate a layout recalculation only when a subviewʼs frame or contentSize has changed
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]) {
            UIScrollView *scrollView = object;
            CGSize oldContentSize = [change[NSKeyValueChangeOldKey] CGSizeValue];
            CGSize newContentSize = scrollView.contentSize;
            if (!CGSizeEqualToSize(newContentSize, oldContentSize)) {
                [self setNeedsLayout];
            }
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(frame))] ||
                   [keyPath isEqualToString:NSStringFromSelector(@selector(bounds))]) {
            UIView *subview = object;
            CGRect oldFrame = [change[NSKeyValueChangeOldKey] CGRectValue];
            CGRect newFrame = subview.frame;
            if (!CGRectEqualToRect(newFrame, oldFrame)) {
                [self setNeedsLayout];
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Layout

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    // Translate the container view's content offset to contentView bounds.
    // This keeps the contentview always centered on the visible portion of the container view's
    // full content size, and avoids the need to make the contentView large enough to fit the
    // container view's full content size.
    self.contentView.frame = self.bounds;
    self.contentView.bounds = (CGRect){ self.contentOffset, self.contentView.bounds.size };
    
    // The logical vertical offset where the current subview (while iterating over all subviews)
    // must be positioned. Subviews are positioned below each other, in the order they were added
    // to the container. For scroll views, we reserve their entire contentSize.height as vertical
    // space. For non-scroll views, we reserve their current frame.size.height as vertical space.
    CGFloat yOffsetOfCurrentSubview = 0.0;
    
    for (UIView *subview in self.subviewsInLayoutOrder)
    {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            UIScrollView *scrollView = (UIScrollView *)subview;
            CGRect frame = scrollView.frame;
            CGPoint contentOffset = scrollView.contentOffset;

            // Translate the logical offset into the sub-scrollview's real content offset and frame size.
            // Methodology:

            // (1) As long as the sub-scrollview has not yet reached the top of the screen, set its scroll position
            // to 0.0 and position it just like a normal view. Its content scrolls naturally as the container
            // scroll view scrolls.
            if (self.contentOffset.y < yOffsetOfCurrentSubview) {
                contentOffset.y = 0.0;
                frame.origin.y = yOffsetOfCurrentSubview;
            }
            // (2) If the user has scrolled far enough down so that the sub-scrollview reaches the top of the
            // screen, position its frame at 0.0 and start adjusting the sub-scrollview's content offset to
            // scroll its content.
            else {
                contentOffset.y = self.contentOffset.y - yOffsetOfCurrentSubview;
                frame.origin.y = self.contentOffset.y;
            }

            // (3) The sub-scrollview's frame should never extend beyond the bottom of the screen, even if its
            // content height is potentially much greater. When the user has scrolled so far that the remaining
            // content height is smaller than the height of the screen, adjust the frame height accordingly.
            CGFloat remainingBoundsHeight = fmax(CGRectGetMaxY(self.bounds) - CGRectGetMinY(frame), 0.0);
            CGFloat remainingContentHeight = fmax(scrollView.contentSize.height - contentOffset.y, 0.0);
            frame.size.height = fmin(remainingBoundsHeight, remainingContentHeight);
            frame.size.width = self.contentView.bounds.size.width;
            
            scrollView.frame = frame;
            scrollView.contentOffset = contentOffset;

            yOffsetOfCurrentSubview += scrollView.contentSize.height;
        }
        else {
            // Normal views are simply positioned at the current offset
            CGRect frame = subview.frame;
            frame.origin.y = yOffsetOfCurrentSubview;
            frame.size.width = self.contentView.bounds.size.width;
            subview.frame = frame;
            
            yOffsetOfCurrentSubview += frame.size.height;
        }
    }
    
    // If our content is shorter than our bounds height, take the contentInset into account to avoid
    // scrolling when it is not needed.
    CGFloat minimumContentHeight = self.bounds.size.height - (self.contentInset.top + self.contentInset.bottom);

    self.contentSize = CGSizeMake(self.bounds.size.width, fmax(yOffsetOfCurrentSubview, minimumContentHeight));
}

@end

#pragma mark - OLEContainerScrollViewContentView

@implementation OLEContainerScrollViewContentView

- (void)didAddSubview:(UIView *)subview
{
    [super didAddSubview:subview];
    if ([self.superview isKindOfClass:[OLEContainerScrollView class]]) {
        [(OLEContainerScrollView *)self.superview didAddSubviewToContainer:subview];
    }
}

- (void)willRemoveSubview:(UIView *)subview
{
    [super willRemoveSubview:subview];
    if ([self.superview isKindOfClass:[OLEContainerScrollView class]]) {
        [(OLEContainerScrollView *)self.superview willRemoveSubviewFromContainer:subview];
    }
}

@end


