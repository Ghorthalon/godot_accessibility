/**
 * iOS backend for DirectTouchServer.
 *
 * Everything that touches UIKit lives here. The rest of the extension never
 * includes a UIKit header, which is what lets the same sources compile as an
 * inert stub on every other platform.
 */

#ifdef IOS_ENABLED

#include "direct_touch_server.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

using namespace godot;

// MARK: - Finding the Godot view
//
// A GDExtension cannot include engine headers, so GDTAppDelegateService is
// resolved through the Objective-C runtime instead of linked against. It
// exposes a populated +viewController class property, and GDTViewController
// exposes godotView - both are plain properties, so KVC reaches them without
// any header at all.
//
// Godot renamed these classes from the Godot* prefix to GDT* during 4.x, hence
// the fallback scan below.

static __weak UIView *_cached_view = nil;

static UIView *_find_view_by_scan(UIView *root) {
	NSString *name = NSStringFromClass([root class]);
	if ([name hasPrefix:@"GDTView"] || [name hasPrefix:@"GodotView"]) {
		return root;
	}
	for (UIView *child in root.subviews) {
		UIView *found = _find_view_by_scan(child);
		if (found != nil) {
			return found;
		}
	}
	return nil;
}

static UIView *_godot_view() {
	// A cached view that has lost its window is a view Godot tore down; drop it
	// and resolve again rather than configuring a detached object.
	UIView *cached = _cached_view;
	if (cached != nil && cached.window != nil) {
		return cached;
	}

	UIView *view = nil;

	for (NSString *service_name in @[ @"GDTAppDelegateService", @"GodotAppDelegate" ]) {
		Class service = NSClassFromString(service_name);
		if (service == nil || ![service respondsToSelector:@selector(viewController)]) {
			continue;
		}
		@try {
			id controller = [service valueForKey:@"viewController"];
			if (controller != nil) {
				id candidate = [controller valueForKey:@"godotView"];
				if ([candidate isKindOfClass:[UIView class]]) {
					view = (UIView *)candidate;
					break;
				}
			}
		} @catch (NSException *e) {
			// KVC on a renamed property. Fall through to the scan.
		}
	}

	// Scenes are iOS 13+. Not worth a pre-13 fallback: direct touch only became
	// per-app gated in iOS 14, so anyone this addon can help is well past 13,
	// and on older systems the KVC path above is the only one that matters.
	if (view == nil) {
		if (@available(iOS 13.0, *)) {
			for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
				if (![scene isKindOfClass:[UIWindowScene class]]) {
					continue;
				}
				for (UIWindow *window in ((UIWindowScene *)scene).windows) {
					view = _find_view_by_scan(window);
					if (view != nil) {
						break;
					}
				}
				if (view != nil) {
					break;
				}
			}
		}
	}

	_cached_view = view;
	return view;
}

// MARK: - Notification observers

@interface GDTDirectTouchObserver : NSObject
@end

@implementation GDTDirectTouchObserver

- (instancetype)init {
	self = [super init];
	if (self) {
		NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
		[center addObserver:self
				   selector:@selector(onVoiceOverStatusChanged:)
					   name:UIAccessibilityVoiceOverStatusDidChangeNotification
					 object:nil];
		[center addObserver:self
				   selector:@selector(onElementFocused:)
					   name:UIAccessibilityElementFocusedNotification
					 object:nil];
		[center addObserver:self
				   selector:@selector(onAnnouncementFinished:)
					   name:UIAccessibilityAnnouncementDidFinishNotification
					 object:nil];
	}
	return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)onVoiceOverStatusChanged:(NSNotification *)note {
	DirectTouchServer *server = DirectTouchServer::get_singleton();
	if (server != nullptr) {
		server->_notify_screen_reader_changed(UIAccessibilityIsVoiceOverRunning());
	}
}

- (void)onElementFocused:(NSNotification *)note {
	DirectTouchServer *server = DirectTouchServer::get_singleton();
	if (server == nullptr) {
		return;
	}
	// Only report focus landing on our surface. VoiceOver posts this for every
	// element it touches, including ones in the system keyboard's window.
	id element = note.userInfo[UIAccessibilityFocusedElementKey];
	UIView *view = _godot_view();
	server->_notify_surface_focused(view != nil && element == view);
}

- (void)onAnnouncementFinished:(NSNotification *)note {
	DirectTouchServer *server = DirectTouchServer::get_singleton();
	if (server == nullptr) {
		return;
	}
	NSString *text = note.userInfo[UIAccessibilityAnnouncementKeyStringValue];
	BOOL success = [note.userInfo[UIAccessibilityAnnouncementKeyWasSuccessful] boolValue];
	server->_notify_announcement_finished(
			String::utf8(text != nil ? text.UTF8String : ""), success == YES);
}

@end

static GDTDirectTouchObserver *_observer = nil;

// MARK: - Main thread dispatch
//
// Godot's iOS main loop is driven by CADisplayLink, so script calls already
// arrive on the UIKit main thread. This is belt and braces for anything that
// ever calls in from a worker.

static void _on_main(void (^block)(void)) {
	if (NSThread.isMainThread) {
		block();
	} else {
		dispatch_async(dispatch_get_main_queue(), block);
	}
}

static NSString *_to_ns(const String &p_string) {
	return [NSString stringWithUTF8String:p_string.utf8().get_data()];
}

// MARK: - Platform hooks

namespace direct_touch_platform {

bool is_supported() {
	return true;
}

bool is_screen_reader_active() {
	return UIAccessibilityIsVoiceOverRunning();
}

void start_observing() {
	_on_main(^{
		if (_observer == nil) {
			_observer = [GDTDirectTouchObserver new];
		}
	});
}

void stop_observing() {
	_on_main(^{
		_observer = nil;
	});
}

void apply_surface(bool p_enabled, const String &p_label, const String &p_hint, int p_options) {
	NSString *label = _to_ns(p_label);
	NSString *hint = _to_ns(p_hint);
	NSUInteger options = (NSUInteger)p_options;

	_on_main(^{
		UIView *view = _godot_view();
		if (view == nil) {
			return;
		}

		if (!p_enabled) {
			view.isAccessibilityElement = NO;
			view.accessibilityTraits &= ~UIAccessibilityTraitAllowsDirectInteraction;
			view.accessibilityLabel = nil;
			view.accessibilityHint = nil;
			if (@available(iOS 17.0, *)) {
				view.accessibilityDirectTouchOptions = UIAccessibilityDirectTouchOptionNone;
			}
			UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
			return;
		}

		// isAccessibilityElement and friends are NSObject(UIAccessibility)
		// properties with default implementations, so they can be set on any
		// instance. No subclassing and no swizzling of GDTView required.
		view.isAccessibilityElement = YES;
		view.accessibilityTraits |= UIAccessibilityTraitAllowsDirectInteraction;
		view.accessibilityLabel = label.length > 0 ? label : nil;
		view.accessibilityHint = hint.length > 0 ? hint : nil;
		if (@available(iOS 17.0, *)) {
			view.accessibilityDirectTouchOptions = (UIAccessibilityDirectTouchOptions)options;
		}

		// Marking the view as an element hides its subviews from VoiceOver,
		// which is what we want: Godot's offscreen GDTKeyboardInputView is not
		// something a player should ever land on. The real system keyboard is
		// in its own UIWindow and stays reachable.
		UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, view);
	});
}

void focus_surface() {
	_on_main(^{
		UIView *view = _godot_view();
		if (view != nil) {
			UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, view);
		}
	});
}

/// Post an announcement, optionally one that only exists to interrupt.
static void _post_announcement(NSString *text, int p_priority) {
	_on_main(^{
		if (@available(iOS 17.0, *)) {
			UIAccessibilityPriority priority = UIAccessibilityPriorityDefault;
			if (p_priority == DirectTouchServer::PRIORITY_HIGH) {
				priority = UIAccessibilityPriorityHigh;
			} else if (p_priority == DirectTouchServer::PRIORITY_LOW) {
				priority = UIAccessibilityPriorityLow;
			}
			NSAttributedString *attributed = [[NSAttributedString alloc]
					initWithString:text
						attributes:@{ UIAccessibilitySpeechAttributeAnnouncementPriority : priority }];
			UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, attributed);
		} else {
			// Pre-17 the only control is the deprecated queue flag, whose
			// default is already "interrupt". Low is the one case worth
			// honouring, since queueing is what it asks for.
			NSAttributedString *attributed = [[NSAttributedString alloc]
					initWithString:text
						attributes:@{
							UIAccessibilitySpeechAttributeQueueAnnouncement :
									@(p_priority == DirectTouchServer::PRIORITY_LOW)
						}];
			UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, attributed);
		}
	});
}

void announce(const String &p_text, int p_priority) {
	_post_announcement(_to_ns(p_text), p_priority);
}

void interrupt_speech() {
	// There is no API to stop VoiceOver mid-sentence. The nearest thing is an
	// announcement that interrupts and has nothing to say - a single space
	// rather than an empty string, because VoiceOver drops empty ones. Default
	// priority, not high: high would interrupt and then refuse to be
	// interrupted itself, which is the opposite of shutting up.
	_post_announcement(@" ", DirectTouchServer::PRIORITY_DEFAULT);
}

} // namespace direct_touch_platform

#endif // IOS_ENABLED
