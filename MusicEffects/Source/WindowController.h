//
//  AudioUnitWrapper.h
//  MusicEffect
//
//  Created by Doug Hyde on 11/19/09.
//  Copyright 2009 Washington University in St. Louis. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>
#include <queue>
#include <vector>

#include "CAComponent.h"
#import "AudioFileReceiver_Protocol.h"

#define MAX_UNITS 12

using namespace std;

@interface HostingWindowController : NSWindowController <NSBrowserDelegate> {
	
	// User Interface Controls
    IBOutlet NSButton *				openFileButton;
	IBOutlet NSButton *				playButton;
	IBOutlet NSButton *				stopButton;
    
    IBOutlet NSBox *				viewContainer;
	NSScrollView *					scrollView;
	
	IBOutlet NSBrowser *			audioUnitBrowser;
	IBOutlet NSPopUpButton *		audioUnitPopup;
    
    IBOutlet NSTextField *			songName;
	NSString *						fileName;
    AudioFileID						fileId;
	BOOL							playing;
	Float64							filePosition;
	
	// Audio Graph Components
	AUGraph							graph;
	AUNode							fileNode, outputNode;
	AudioUnit						fileUnit, outputUnit;
	
	CAComponent *					allAudioUnits;
	AudioUnit						activeUnits[MAX_UNITS];
	AUNode							activeNodes[MAX_UNITS];
	NSString *						activeNames[MAX_UNITS];
	
	vector<int>						path;
	queue<int>						freeList;
}



#pragma mark IB Actions
- (IBAction) addAudioUnit:(id)sender;
- (IBAction) deleteAudioUnit:(id)sender;

- (IBAction) playPause:(id)sender;
- (IBAction) stopMusic: (id)sender;
- (IBAction) selectAudioUnit :(id)sender;
- (IBAction) selectFile :(id)sender;

- (void) createGraph;
- (void) destroyGraph;
- (void) showAudioUnit:(AudioUnit)inAU;
- (void) prepareFileAudioUnit;
- (void) buildAudioUnitList;
- (void) loadAudioFile:(NSString *)inAudioFileName;

@end
