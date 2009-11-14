//
//  CAUHWindowController.h
//  host
//
//  Created by Doug Hyde on 10/15/09.
//  Copyright 2009 Washington University in St. Louis. All rights reserved.
//


#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>

#import <Cocoa/Cocoa.h>

#import "AudioFileReceiver_Protocol.h"


#define FILE 0
#define SPLITTER 1
#define VOLUME 2
#define SPEAKER 3
#define MICROPHONE 4
#define FILTER_MICROPHONE 5
#define COMPARISON 6
#define FILTER_FILE 7
#define INPUT_MIXER 8
#define OUTPUT_MIXER 9

@class AudioFileListView;
class CAComponent;

@interface HostingWindowController : NSWindowController <AudioFileReceiver, NSWindowDelegate> {
    // IB: AU Selection
    IBOutlet NSButton *				uiAudioFileButton;
    IBOutlet NSBox *				uiAUViewContainer;
	IBOutlet NSMatrix *				uiAUViewSelect;
    
    // IB: Audio Transport
    IBOutlet NSButton *				uiPlayStopButton;
    IBOutlet AudioFileListView *	uiAudioFileTableView;
    IBOutlet NSTextField *			uiAudioFileNowPlayingName;
    
    // Post-nib view manufacturing
    NSScrollView *					mScrollView;
    
    // AU Tracking
    NSMutableArray *				mAudioFileList;
    
    // AudioFile / AUGraph members
	AudioFileID						mAFID;
	AUGraph							mGraph;
	
	AUNode node[10];
	AudioUnit unit[10];
	
	AudioDeviceID					inputDevice;
	AudioDeviceID					outputDevice;
	

}

- (void)createGraph;
- (void)startGraph;
- (void)stopGraph;
- (void)destroyGraph;
- (void)prepareFileAU;

- (void)loadAudioFile:(NSString *)inAudioFileName;

- (void)showCocoaViewForAU:(AudioUnit)inAU;
- (IBAction)iaPlayStopButtonPressed:(id)sender;
- (IBAction)switchAUView:(NSMatrix*)sender;

- (int)numberOfRowsInTableView:(NSTableView *)inTableView;
- (id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)inTableColumn row:(int)inRow;

- (void)synchronizePlayStopButton;
- (void)addLinkToFiles:(NSArray *)inFiles;
-(void)cleanup;





#pragma mark IB Actions
- (IBAction)iaPlayStopButtonPressed:(id)sender;
- (IBAction)switchAUView:(NSMatrix*)sender;

@end
