//
//  CAUHWindowController.mm
//  host
//
//  Created by Doug Hyde on 10/15/09.
//  Copyright 2009 Washington University in St. Louis. All rights reserved.
//


#import <CoreAudioKit/CoreAudioKit.h>
#import <AudioUnit/AUCocoaUIView.h>

#include "CAComponent.h"
#include "CAComponentDescription.h"
#include "CAStreamBasicDescription.h"

#import "CAUHWindowController.h"
#import "AudioFileListView.h"



void AudioFileNotificationHandler (void *inRefCon, OSStatus inStatus) {
    HostingWindowController *SELF = (HostingWindowController *)inRefCon;
    [SELF performSelectorOnMainThread:@selector(iaPlayStopButtonPressed:) withObject:SELF waitUntilDone:NO];
}


void filePlayCompletionProc (void *userData, ScheduledAudioFileRegion *fileRegion, OSStatus result) {
	printf("File completed!\n");
	HostingWindowController* SELF = (HostingWindowController*)userData;
	[SELF stopGraph];
}



@implementation HostingWindowController



+ (BOOL)plugInClassIsValid:(Class) pluginClass {
	if ([pluginClass conformsToProtocol:@protocol(AUCocoaUIBase)]) {
		if ([pluginClass instancesRespondToSelector:@selector(interfaceVersion)] &&
			[pluginClass instancesRespondToSelector:@selector(uiViewForAudioUnit:withSize:)]) {
			return YES;
		}
	}
    return NO;
}


#pragma mark -
#pragma mark Audio Graph

/** createGraph
 * Constructs all of the AudioNodes and AudioUnits and the initial AudioGraph. */
- (void)createGraph {
	[self synchronizePlayStopButton]; // TODO place somewhere better
	
	verify_noerr (NewAUGraph(&mGraph));
	CAComponentDescription desc;
	
	// Output
	desc = CAComponentDescription (	kAudioUnitType_Output,
									kAudioUnitSubType_DefaultOutput,
									kAudioUnitManufacturer_Apple);
	
	// Create a node to represent the IO device
	verify_noerr (AUGraphAddNode(mGraph, &desc, &node[SPEAKER]));
	
	// File Input
	desc = CAComponentDescription (	kAudioUnitType_Generator,
									kAudioUnitSubType_AudioFilePlayer,
									kAudioUnitManufacturer_Apple);
	verify_noerr (AUGraphAddNode(mGraph, &desc, &node[FILE]));
	
	
	// Initialize basic graph
	verify_noerr (AUGraphOpen(mGraph));
    verify_noerr (AUGraphNodeInfo(mGraph, node[FILE], NULL, &unit[FILE]));
    verify_noerr (AUGraphNodeInfo(mGraph, node[SPEAKER], NULL, &unit[SPEAKER]));
	
	
	// Splitter
	desc = CAComponentDescription (kAudioUnitType_FormatConverter,
								   kAudioUnitSubType_Splitter,
								   kAudioUnitManufacturer_Apple);
	verify_noerr (AUGraphAddNode(mGraph, &desc, &node[SPLITTER]));
	verify_noerr (AUGraphNodeInfo(mGraph, node[SPLITTER], NULL, &unit[SPLITTER]));
								   

	// File High-Pass
	desc = CAComponentDescription (kAudioUnitType_Effect,
								   kAudioUnitSubType_HighPassFilter,
								   kAudioUnitManufacturer_Apple);
    verify_noerr (AUGraphAddNode(mGraph, &desc, &node[FILTER_FILE]));
	verify_noerr (AUGraphNodeInfo(mGraph, node[FILTER_FILE], NULL, &unit[FILTER_FILE]));

	
	// Microphone High-Pass
	desc = CAComponentDescription (kAudioUnitType_Effect,
								   kAudioUnitSubType_HighPassFilter,
								   kAudioUnitManufacturer_Apple);
    verify_noerr (AUGraphAddNode(mGraph, &desc, &node[FILTER_MICROPHONE]));
	verify_noerr (AUGraphNodeInfo(mGraph, node[FILTER_MICROPHONE], NULL, &unit[FILTER_MICROPHONE]));
	
	// Comparison TODO
	
	
	// Volume Regulation TODO
	
	
	// Microphone TODO
	
    verify_noerr (AUGraphUpdate (mGraph, NULL));
}


/** startGraph
 * Connect all of the nodes to form the actual graph. Begin file playback if possible. */
- (void)startGraph {
	verify_noerr (AUGraphConnectNodeInput (mGraph, node[FILTER_FILE], 0, node[SPEAKER], 0));
	verify_noerr (AUGraphConnectNodeInput (mGraph, node[SPLITTER], 0, node[FILTER_FILE], 0));
	verify_noerr (AUGraphConnectNodeInput (mGraph, node[FILE], 0, node[SPLITTER], 0));
	
	verify_noerr (AUGraphUpdate (mGraph, NULL) == noErr);
    verify_noerr (AUGraphInitialize(mGraph) == noErr);
	
	[self prepareFileAU];
	
    verify_noerr (AUGraphStart(mGraph) == noErr);
}


/** stopGraph
 * Stop the graph */
- (void)stopGraph {
	verify_noerr (AUGraphStop(mGraph));
	verify_noerr (AUGraphUninitialize(mGraph));
	verify_noerr (AUGraphClearConnections (mGraph));
	verify_noerr (AUGraphUpdate (mGraph, NULL));
	if(mAFID)
		verify_noerr (AudioFileClose(mAFID));
}



- (void)destroyGraph {
	// stop graph if necessary
    Boolean isRunning = FALSE;
	verify_noerr (AUGraphIsRunning(mGraph, &isRunning));
	if (isRunning)
		[self stopGraph];
	
	// close and destroy
	verify_noerr (AUGraphClose(mGraph));
	verify_noerr (DisposeAUGraph(mGraph));
}



#pragma mark -
#pragma mark File Playback


- (void)prepareFileAU {	
	
	// calculate the duration
	UInt64 nPackets;
	UInt32 propsize = sizeof(nPackets);
	verify_noerr (AudioFileGetProperty(mAFID, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets));
	
	CAStreamBasicDescription fileFormat;
	propsize = sizeof(CAStreamBasicDescription);
	verify_noerr (AudioFileGetProperty(mAFID, kAudioFilePropertyDataFormat, &propsize, &fileFormat));
		
	//Float64 fileDuration = (nPackets * fileFormat.mFramesPerPacket) / fileFormat.mSampleRate;

	ScheduledAudioFileRegion rgn;
	memset (&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
	rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
	rgn.mTimeStamp.mSampleTime = 0;
	rgn.mCompletionProc = filePlayCompletionProc;
	rgn.mCompletionProcUserData = self;
	rgn.mAudioFile = mAFID;
	rgn.mLoopCount = 1;
	rgn.mStartFrame = 0;
	rgn.mFramesToPlay = UInt32(nPackets * fileFormat.mFramesPerPacket);
		
		// tell the file player AU to play all of the file
	verify_noerr (AudioUnitSetProperty(	unit[FILE], 
										kAudioUnitProperty_ScheduledFileRegion, 
										kAudioUnitScope_Global, 
										0,
										&rgn, 
										sizeof(rgn)));
	
	// prime the fp AU with default values
	UInt32 defaultVal = 0;
	verify_noerr (AudioUnitSetProperty(	unit[FILE],
										kAudioUnitProperty_ScheduledFilePrime, 
										kAudioUnitScope_Global,
										0,
										&defaultVal, 
										sizeof(defaultVal)));

	// tell the fp AU when to start playing (this ts is in the AU's render time stamps; -1 means next render cycle)
	AudioTimeStamp startTime;
	memset (&startTime, 0, sizeof(startTime));
	startTime.mFlags = kAudioTimeStampSampleTimeValid;
	startTime.mSampleTime = -1;
	verify_noerr (AudioUnitSetProperty(	unit[FILE],
										kAudioUnitProperty_ScheduleStartTimeStamp, 
										kAudioUnitScope_Global, 
										0,
										&startTime, 
										sizeof(startTime)));
										
	verify_noerr (AudioUnitSetProperty(	unit[FILE],
										kAudioUnitProperty_ScheduleStartTimeStamp, 
										kAudioUnitScope_Global, 
										0,
										&startTime, 
										sizeof(startTime)));									
}


- (void)loadAudioFile:(NSString *)inAudioFileName {
	FSRef destFSRef;
	UInt8 *pathName = (UInt8 *)[inAudioFileName UTF8String];

	verify_noerr (FSPathMakeRef(pathName, &destFSRef, NULL));
	verify_noerr (AudioFileOpen(&destFSRef, fsRdPerm, 0, &mAFID));

	verify_noerr (AudioUnitSetProperty(	unit[FILE], 
										kAudioUnitProperty_ScheduledFileIDs,
										kAudioUnitScope_Global,
										0,
										&mAFID,
										sizeof(mAFID) ));
}









#pragma mark -
#pragma mark UI

- (void)showCocoaViewForAU:(AudioUnit)inAU {
	// get AU's Cocoa view property
    UInt32 						dataSize;
    Boolean 					isWritable;
    AudioUnitCocoaViewInfo *	cocoaViewInfo = NULL;
    UInt32						numberOfClasses;
    
    OSStatus result = AudioUnitGetPropertyInfo(	inAU,
											   kAudioUnitProperty_CocoaUI,
											   kAudioUnitScope_Global, 
											   0,
											   &dataSize,
											   &isWritable );
    
    numberOfClasses = (dataSize - sizeof(CFURLRef)) / sizeof(CFStringRef);
    
    NSURL 	 *	CocoaViewBundlePath = nil;
    NSString *	factoryClassName = nil;
    
	// Does view have custom Cocoa UI?
    if ((result == noErr) && (numberOfClasses > 0) ) {
        cocoaViewInfo = (AudioUnitCocoaViewInfo *)malloc(dataSize);
        if(AudioUnitGetProperty(		inAU,
								kAudioUnitProperty_CocoaUI,
								kAudioUnitScope_Global,
								0,
								cocoaViewInfo,
								&dataSize) == noErr) {
            CocoaViewBundlePath	= (NSURL *)cocoaViewInfo->mCocoaAUViewBundleLocation;
			
			// we only take the first view in this example.
            factoryClassName	= (NSString *)cocoaViewInfo->mCocoaAUViewClass[0];
        } else {
            if (cocoaViewInfo != NULL) {
				free (cocoaViewInfo);
				cocoaViewInfo = NULL;
			}
        }
    }
	
	NSView *AUView = nil;
	BOOL wasAbleToLoadCustomView = NO;
	
	// [A] Show custom UI if view has it
	if (CocoaViewBundlePath && factoryClassName) {
		NSBundle *viewBundle  	= [NSBundle bundleWithPath:[CocoaViewBundlePath path]];
		if (viewBundle == nil) {
			NSLog (@"Error loading AU view's bundle");
		} else {
			Class factoryClass = [viewBundle classNamed:factoryClassName];
			NSAssert (factoryClass != nil, @"Error getting AU view's factory class from bundle");
			
			// make sure 'factoryClass' implements the AUCocoaUIBase protocol
			NSAssert(	[HostingWindowController plugInClassIsValid:factoryClass],
					 @"AU view's factory class does not properly implement the AUCocoaUIBase protocol");
			
			// make a factory
			id factoryInstance = [[[factoryClass alloc] init] autorelease];
			NSAssert (factoryInstance != nil, @"Could not create an instance of the AU view factory");
			// make a view
			AUView = [factoryInstance	uiViewForAudioUnit:inAU
												withSize:[[mScrollView contentView] bounds].size];
			
			// cleanup
			[CocoaViewBundlePath release];
			if (cocoaViewInfo) {
				UInt32 i;
				for (i = 0; i < numberOfClasses; i++)
					CFRelease(cocoaViewInfo->mCocoaAUViewClass[i]);
				
				free (cocoaViewInfo);
			}
			wasAbleToLoadCustomView = YES;
		}
	}
	
	if (!wasAbleToLoadCustomView) {
		// [B] Otherwise show generic Cocoa view
		AUView = [[AUGenericView alloc] initWithAudioUnit:inAU];
		[(AUGenericView *)AUView setShowsExpertParameters:YES];
		[AUView autorelease];
    }
	
	// Display view
	NSRect viewFrame = [AUView frame];
	NSSize frameSize = [NSScrollView	frameSizeForContentSize:viewFrame.size
									   hasHorizontalScroller:[mScrollView hasHorizontalScroller]
										 hasVerticalScroller:[mScrollView hasVerticalScroller]
												  borderType:[mScrollView borderType]];
	
	NSRect newFrame;
	newFrame.origin = [mScrollView frame].origin;
	newFrame.size = frameSize;
	
	NSRect currentFrame = [mScrollView frame];
	[mScrollView setFrame:newFrame];
	[mScrollView setDocumentView:AUView];
	
	NSSize oldContentSize = [[[self window] contentView] frame].size;
	NSSize newContentSize = oldContentSize;
	newContentSize.width += (newFrame.size.width - currentFrame.size.width);
	newContentSize.height += (newFrame.size.height - currentFrame.size.height);
	
	[[self window] setContentSize:newContentSize];
}


- (void)awakeFromNib {
    mAudioFileList = [[NSMutableArray alloc] init];
    
    // create scroll-view
    NSRect frameRect = [[uiAUViewContainer contentView] frame];
    mScrollView = [[[NSScrollView alloc] initWithFrame:frameRect] autorelease];
    [mScrollView setDrawsBackground:NO];
    [mScrollView setHasHorizontalScroller:YES];
    [mScrollView setHasVerticalScroller:YES];
    [uiAUViewContainer setContentView:mScrollView];
    
    // dispatched setup
    [self createGraph];
	
	[self showCocoaViewForAU: unit[FILTER_FILE]];
	
    
	// make this the app. delegate
	[NSApp setDelegate:self];
	
	[[self window] setDelegate: self];
}


- (IBAction)iaPlayStopButtonPressed:(id)sender {
    if (sender == self) {
        // change button icon manually if this function is called internally
        [uiPlayStopButton setState:([uiPlayStopButton state] == NSOffState) ? NSOnState : NSOffState];
    }
    
    Boolean isRunning = FALSE;
	verify_noerr (AUGraphIsRunning(mGraph, &isRunning));
	
	// [1] if the AUGraph is running, stop it
    if (isRunning) {
        // stop graph, update UI & return
		[self stopGraph];

        return;
    }
    
	// [2] otherwise start the AUGraph
    // load file
	int selectedRow = [uiAudioFileTableView selectedRow];
	if ( (selectedRow < 0) || ([mAudioFileList count] == 0) ) return;	// no file selected
		
	NSString *audioFileName = (NSString *)[mAudioFileList objectAtIndex:selectedRow];
	[self loadAudioFile:audioFileName];
		
	// set filename in UI
	[uiAudioFileNowPlayingName setStringValue:[audioFileName lastPathComponent]];
    
	[self startGraph];
}


- (IBAction)switchAUView:(NSMatrix*)sender {
	//if ([sender selectedColumn] == 0) {
	//	[self showCocoaViewForAU: unit[FILE]];
	//} else if ([sender selectedColumn] == 1) {
		[self showCocoaViewForAU: unit[FILTER_FILE]];
	//}
}



- (int)numberOfRowsInTableView:(NSTableView *)inTableView {
    int count = [mAudioFileList count];
    return (count > 0) ? count : 1;
}


- (id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)inTableColumn row:(int)inRow {
    int count = [mAudioFileList count];
    return (count > 0) ?	[(NSString *)[mAudioFileList objectAtIndex:inRow] lastPathComponent] :
                            @"< drag audio files here >";
}


- (void)synchronizePlayStopButton {
    [uiPlayStopButton setEnabled:[mAudioFileList count] > 0];
}


- (void)addLinkToFiles:(NSArray *)inFiles {
    [mAudioFileList addObjectsFromArray:inFiles];
    [self synchronizePlayStopButton];
    [uiAudioFileTableView reloadData];
}


#pragma mark -
#pragma mark Cleanup


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)inSender {
	return YES;
}


- (void) windowWillClose:(NSNotification *) aNotification {
	[self cleanup];
}



-(void)cleanup {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	
    [mAudioFileList release];
    
	if(mAFID)
		verify_noerr(AudioFileClose(mAFID));
    
    [self destroyGraph];
}

@end
