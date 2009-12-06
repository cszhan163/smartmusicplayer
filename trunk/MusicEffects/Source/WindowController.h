//
//  AudioUnitWrapper.h
//  MusicEffect
//
//  Created by Doug Hyde on 10/3/09.
//  Copyright 2009 Washington University in St. Louis. All rights reserved.
//


#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>

#import "AudioFileReceiver_Protocol.h"

class CAComponent;

#define MAX_UNITS 12

@interface HostingWindowController : NSWindowController <NSBrowserDelegate> {
	
    IBOutlet NSButton *				openFileButton;
	IBOutlet NSButton *				playButton;
	IBOutlet NSButton *				stopButton;
    
    IBOutlet NSBox *				uiAUViewContainer;
	
	// Audio Graph Configuration
	IBOutlet NSBrowser *			audioUnitBrowser;
	IBOutlet NSPopUpButton *		audioUnitPopup;
    
    IBOutlet NSTextField *			songName;
	NSString *						fileName;
    
    NSScrollView *					mScrollView;

	AudioFileID						mAFID;
	AUGraph							mGraph;
	AUNode							mFileNode, mOutputNode;
	AudioUnit						mFileUnit, mOutputUnit;
	
	CAComponent *					allAudioUnits;
	AudioUnit						activeUnits[MAX_UNITS];
	AUNode							activeNodes[MAX_UNITS];
	NSString *						activeNames[MAX_UNITS];
	int								numActiveUnits;
}



#pragma mark IB Actions
- (IBAction) addAudioUnit:(id)sender;
- (IBAction) playPause:(id)sender;

- (IBAction) stopMusic: (id)sender;
- (IBAction) selectAudioUnit :(id)sender;
- (IBAction) selectFile :(id)sender;



+ (BOOL) plugInClassIsValid:(Class) pluginClass;
- (void) cleanup;
- (void) createGraph;
- (void) startGraph;
- (void) stopGraph;
- (void) destroyGraph;
- (void) showAudioUnit:(AudioUnit)inAU;
- (void) prepareFileAudioUnit;
- (void) synchronizePlayStopButton;
- (void) buildAudioUnitList;
- (void) loadAudioFile:(NSString *)inAudioFileName;

@end
