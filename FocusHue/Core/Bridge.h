//
//  Bridge.h
//  FocusHue
//
//  Bridging header for private MediaAccessibility framework functions
//  Based on brettferdosi/grayscale implementation
//

#ifndef Bridge_h
#define Bridge_h

#import <Foundation/Foundation.h>

// MARK: - CoreGraphics (Public, but undocumented)

// These functions don't require a private framework. The filter they enable
// is not the same one used by the current system (it seems a little darker),
// and calling these does not make the change persist through sleep.
extern _Bool CGDisplayUsesForceToGray(void);
extern void CGDisplayForceToGray(_Bool enable);

// MARK: - MediaAccessibility Framework Functions

// These functions are exported by /System/Library/Frameworks/MediaAccessibility.framework/
// They set the preferences that enable the grayscale filter.

// category enabled == whether or not the filter of the selected type is active
extern _Bool MADisplayFilterPrefGetCategoryEnabled(int filter);
extern void  MADisplayFilterPrefSetCategoryEnabled(int filter, _Bool enable);
extern int MADisplayFilterPrefGetType(int filter);
extern void MADisplayFilterPrefSetType(int filter, int type);

// Filter constants
static const int SYSTEM_FILTER = 0x1;
static const int GRAYSCALE_TYPE = 0x1;

// MARK: - libUniversalAccess.dylib

// The universalaccessd daemon (/usr/sbin/universalaccessd) listens for the MediaAccessibility
// preference change event and actually toggles the grayscale filter.
//
// The daemon is not always running or listening for these changes, so we use the following
// function from /usr/lib/libUniversalAccess.dylib to kick it awake after making the changes.
// (it seems to check and respond to the preferences when it is first woken up; wake it up
// after the changes to avoid potential races)

extern void _UniversalAccessDStart(int magic);

static const int UNIVERSALACCESSD_MAGIC = 0x8;

#endif /* Bridge_h */
