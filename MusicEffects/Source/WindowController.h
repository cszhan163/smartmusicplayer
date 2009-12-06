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

@class AudioFileListView;
class CAComponent;

#define MAX_UNITS 12

@interface HostingWindowController : NSWindowController <AudioFileReceiver, NSBrowserDelegate> {
	
    IBOutlet NSButton *				uiAudioFileButton;
    IBOutlet NSPopUpButton *		audioUnitPopup;
    IBOutlet NSBox *				uiAUViewContainer;
	
	// Audio Graph Configuration
	IBOutlet NSBrowser *			audioUnitBrowser;
	IBOutlet NSSegmentedControl *	audioUnitBrowserControl;
    
	IBOutlet NSButton *				uiPlayStop;
	

    IBOutlet NSButton *				uiPlayStopButton;
    IBOutlet AudioFileListView *	uiAudioFileTableView;
    IBOutlet NSTextField *			songName;
    
    NSScrollView *					mScrollView;
    
    NSMutableArray *				mAudioFileList;

	AudioFileID						mAFID;
	AUGraph							mGraph;
	AUNode							mFileNode, mixerNode, mOutputNode;
	AudioUnit						mFileUnit, mixerUnit, mOutputUnit;
	
	CAComponent *					allAudioUnits;
	AudioUnit						activeUnits[MAX_UNITS];
	AUNode							activeNodes[MAX_UNITS];
	NSString *						activeNames[MAX_UNITS];
	int								numActiveUnits;
}


- (void)stopGraph;

#pragma mark IB Actions
- (IBAction) addAudioUnit:(id)sender;
- (IBAction)iaPlayStopButtonPressed:(id)sender;

- (IBAction) stopMusic: (id)sender;
- (IBAction) selectAudioUnit :(id)sender;



+ (BOOL)plugInClassIsValid:(Class) pluginClass;
- (void)cleanup;
- (void)createGraph;
- (void)startGraph;
- (void)stopGraph;
- (void)destroyGraph;
- (void)showAudioUnit:(AudioUnit)inAU;
- (void)prepareFileAudioUnit;
- (void)synchronizePlayStopButton;
- (void)buildAudioUnitList;
- (void)addLinkToFiles:(NSArray *)inFiles;
- (void)loadAudioFile:(NSString *)inAudioFileName;

@end
