//
//  AudioUnitWrapper.h
//  MusicEffect
//
//  Created by Doug Hyde on 11/19/09.
//  Copyright 2009 Washington University in St. Louis. All rights reserved.
//


#import <CoreAudioKit/CoreAudioKit.h>
#import <AudioUnit/AUCocoaUIView.h>

#include "CAComponentDescription.h"
#include "CAStreamBasicDescription.h"

#import "WindowController.h"


@implementation HostingWindowController

/** awakeFromNib
 Initializes everything and gets it ready for running. */
- (void)awakeFromNib {
	playing = NO;
	filePosition = 0;
	for (int i=0; i<MAX_UNITS; ++i)
		freeList.push(i);
    
    // Create AudioUnit view scroll view
    NSRect frameRect = [[viewContainer contentView] frame];
    scrollView = [[[NSScrollView alloc] initWithFrame:frameRect] autorelease];
    [scrollView setDrawsBackground:NO];
    [scrollView setHasHorizontalScroller: NO];
    [scrollView setHasVerticalScroller:YES];
    [viewContainer setContentView:scrollView];
    
    // Initialize audio components
	[self createGraph];
	[self buildAudioUnitList];
	[audioUnitBrowser setDoubleAction: @selector(selectAudioUnit:)];
	
	// Set Delegate
	[NSApp setDelegate:self];
}


#pragma mark -
#pragma mark Audio Graph


/** createGraph
 Sets up the static components of the graph and starts it. */
- (void)createGraph {
	verify_noerr (NewAUGraph(&graph));
	
	CAComponentDescription desc;
	desc = CAComponentDescription (kAudioUnitType_Output,
								   kAudioUnitSubType_DefaultOutput,
								   kAudioUnitManufacturer_Apple);
	verify_noerr (AUGraphAddNode(graph, &desc, &outputNode));
	
	desc = CAComponentDescription (kAudioUnitType_Generator,
								   kAudioUnitSubType_AudioFilePlayer,
								   kAudioUnitManufacturer_Apple);
	verify_noerr (AUGraphAddNode(graph, &desc, &fileNode));
	
	verify_noerr (AUGraphOpen(graph));
    verify_noerr (AUGraphNodeInfo(graph, fileNode, NULL, &fileUnit));
    verify_noerr (AUGraphNodeInfo(graph, outputNode, NULL, &outputUnit));
	
	verify_noerr (AUGraphConnectNodeInput (graph, fileNode, 0, outputNode, 0));
	verify_noerr (AUGraphUpdate (graph, NULL));
	
    verify_noerr (AUGraphInitialize(graph) == noErr);
    verify_noerr (AUGraphStart(graph) == noErr);
}


/** destroyGraph
 Closes the graph and destroys the components. */
- (void)destroyGraph {
    Boolean isRunning = FALSE;
	verify_noerr (AUGraphIsRunning(graph, &isRunning));
	if (isRunning) {
		verify_noerr (AUGraphStop(graph));
		verify_noerr (DisposeAUGraph(graph));
		graph = 0;
		if(fileId)
			verify_noerr (AudioFileClose(fileId));
	}
	verify_noerr (AUGraphClose(graph));
	verify_noerr (DisposeAUGraph(graph));
}


/** addAudioUnit
 Adds a new AudioUnit of the selected type to the end of the audio graph and
 displays it on the GUI. */
- (IBAction) addAudioUnit :(id)sender {
	// Determine AudioUnit to add
	int index = [audioUnitPopup indexOfSelectedItem] - 1;
	if (index < 0)
		return;
	AudioComponentDescription desc = allAudioUnits[index].Desc();
	
	// Determine where to store
	int i = freeList.front();
	freeList.pop();
	path.insert(path.end(), i);
	
	// Create new AudioUnit
	verify_noerr (AUGraphAddNode(graph, &desc, &activeNodes[i]));
	verify_noerr (AUGraphNodeInfo(graph, activeNodes[i], NULL, &activeUnits[i]));
	verify_noerr (AudioUnitInitialize(activeUnits[i]));
	
	activeNames[i] = (NSString*)allAudioUnits[index].GetAUName();
	[audioUnitBrowser reloadColumn:0];
	
	// Connect to graph
	if (path.size() == 1) {
		verify_noerr (AUGraphDisconnectNodeInput(graph, outputNode, 0));
		verify_noerr (AUGraphConnectNodeInput (graph, activeNodes[i], 0, outputNode, 0));
		verify_noerr (AUGraphConnectNodeInput (graph, fileNode, 0, activeNodes[i], 0));
	} else {
		int j = path[path.size()-2];
		verify_noerr (AUGraphDisconnectNodeInput(graph, outputNode, 0));
		verify_noerr (AUGraphConnectNodeInput (graph, activeNodes[i], 0, outputNode, 0));
		verify_noerr (AUGraphConnectNodeInput (graph, activeNodes[j], 0, activeNodes[i], 0));
	}
	
	// Update graph
	AUGraphUpdate (graph, NULL);
	CAShow(graph);	// DEBUG output
	
	// Show AudioUnit
	[self showAudioUnit: activeUnits[i]];
}


/** deleteAudioUnit
 Removes the AudioUnit from the audio graph and updates the display. */
- (IBAction) deleteAudioUnit :(id)sender {
	if (path.size() == 0)
		return;
	
	// Adjust the path representation
	unsigned int i = [audioUnitBrowser selectedRowInColumn:0];
	int j = path[i];
	bool front = i==0;
	bool end = (unsigned)i==path.size()-1;
	for (vector<int>::iterator it=path.begin(); it<path.end(); it++)
		if (*it == j) {
			path.erase(it);
			break;
		}
	freeList.push(j);
	[audioUnitBrowser reloadColumn:0];
	
	// Update the graph
	verify_noerr (AUGraphRemoveNode(graph, activeNodes[j]));
	if (path.size() == 0) {
		verify_noerr (AUGraphConnectNodeInput (graph, fileNode, 0, outputNode, 0));
	} else if (front) {
		verify_noerr (AUGraphConnectNodeInput (graph, fileNode, 0, activeNodes[path[i]], 0));
	} else if (end) {
		int k = path[i-1];
		verify_noerr (AUGraphConnectNodeInput (graph, activeNodes[k], 0, outputNode, 0));
	} else {
		int k = path[i];
		int m = path[i-1];
		verify_noerr (AUGraphConnectNodeInput (graph, activeNodes[m], 0, activeNodes[k], 0));
	}
	
	AUGraphUpdate (graph, NULL);
	CAShow(graph);	// DEBUG output
	
	// Show 1st AudioUnit
	if (path.size() > 0)
		[self showAudioUnit: activeUnits[path[0]]];
	else {
		NSView * view = [[NSView alloc] init];
		[scrollView setDocumentView:view];
		[view release];
	}
}



#pragma mark -
#pragma mark Audio Unit


/** showAudioUnit
 Displays the Cocoa view for the specified audio unit in the NSBox. */
- (void) showAudioUnit:(AudioUnit)inAU {
	// get AU's Cocoa view property
    UInt32 dataSize;
    Boolean isWritable;
    AudioUnitCocoaViewInfo * cocoaViewInfo = NULL;
    UInt32 numberOfClasses;
    
    OSStatus result = AudioUnitGetPropertyInfo(inAU,
											   kAudioUnitProperty_CocoaUI,
											   kAudioUnitScope_Global, 
											   0, &dataSize, &isWritable);
    
    numberOfClasses = (dataSize - sizeof(CFURLRef)) / sizeof(CFStringRef);
    NSURL *	CocoaViewBundlePath = nil;
    NSString * factoryClassName = nil;
    
	// Does view have custom Cocoa UI?
    if ((result == noErr) && (numberOfClasses > 0) ) {
        cocoaViewInfo = (AudioUnitCocoaViewInfo *)malloc(dataSize);
        if(AudioUnitGetProperty(inAU, kAudioUnitProperty_CocoaUI,
								kAudioUnitScope_Global,
								0, cocoaViewInfo, &dataSize) == noErr) {
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
	
	NSView * AUView = nil;
	BOOL wasAbleToLoadCustomView = NO;
	
	// [A] Show custom UI if view has it
	if (CocoaViewBundlePath && factoryClassName) {
		NSBundle *viewBundle  	= [NSBundle bundleWithPath:[CocoaViewBundlePath path]];
		if (viewBundle == nil) {
			NSLog (@"Error loading AU view's bundle");
		} else {
			Class factoryClass = [viewBundle classNamed:factoryClassName];
			NSAssert (factoryClass != nil, @"Error getting AU view's factory class from bundle");
			
			// make a factory
			id factoryInstance = [[[factoryClass alloc] init] autorelease];
			NSAssert (factoryInstance != nil, @"Could not create an instance of the AU view factory");
			// make a view
			AUView = [factoryInstance uiViewForAudioUnit:inAU withSize:[[scrollView contentView] bounds].size];
			
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
		// Show generic Cocoa view
		AUView = [[AUGenericView alloc] initWithAudioUnit:inAU];
		[(AUGenericView *)AUView setShowsExpertParameters:YES];
		[AUView autorelease];
    }
	
	// Resize AudioUnit View
	NSRect frame = [AUView frame];
	if ([AUView autoresizingMask] & NSViewWidthSizable)
		frame.size.width = [[scrollView contentView] frame].size.width;
	if ([AUView autoresizingMask] & NSViewHeightSizable)
		frame.size.height = [[scrollView contentView] frame].size.height;
	
	[AUView setFrame: frame];
	[scrollView setDocumentView:AUView];
	
	NSRect scrollFrame = [scrollView frame];
	scrollFrame.size = [NSScrollView frameSizeForContentSize: frame.size
							hasHorizontalScroller: [scrollView hasHorizontalScroller]
							hasVerticalScroller: [scrollView hasVerticalScroller]
							borderType: [scrollView borderType]];
	
	[scrollView setFrame: scrollFrame];
}


/** prepareFileAudioUnit
 Configures the file playing and begins playing from the frame specified by filePosition. */
- (void)prepareFileAudioUnit {	
	// Calculate the duration
	UInt64 nPackets;
	UInt32 propsize = sizeof(nPackets);
	verify_noerr (AudioFileGetProperty(fileId, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets));
	
	CAStreamBasicDescription fileFormat;
	propsize = sizeof(CAStreamBasicDescription);
	verify_noerr (AudioFileGetProperty(fileId, kAudioFilePropertyDataFormat, &propsize, &fileFormat));
	
	ScheduledAudioFileRegion rgn;
	memset (&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
	rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
	rgn.mTimeStamp.mSampleTime = 0;
	rgn.mCompletionProc = NULL;
	rgn.mCompletionProcUserData = NULL;
	rgn.mAudioFile = fileId;
	rgn.mLoopCount = 1;
	rgn.mStartFrame = filePosition;
	rgn.mFramesToPlay = UInt32(nPackets * fileFormat.mFramesPerPacket);
	
	// Play entire file
	verify_noerr (AudioUnitSetProperty(	fileUnit, 
									   kAudioUnitProperty_ScheduledFileRegion, 
									   kAudioUnitScope_Global, 
									   0, &rgn, sizeof(rgn)));
	
	// Set default values
	UInt32 defaultVal = 0;
	verify_noerr (AudioUnitSetProperty(	fileUnit,
									   kAudioUnitProperty_ScheduledFilePrime, 
									   kAudioUnitScope_Global,
									   0, &defaultVal, sizeof(defaultVal)));
	
	// When to start playing (-1 means next render cycle)
	AudioTimeStamp startTime;
	memset (&startTime, 0, sizeof(startTime));
	startTime.mFlags = kAudioTimeStampSampleTimeValid;
	startTime.mSampleTime = -1;
	verify_noerr (AudioUnitSetProperty(	fileUnit,
									   kAudioUnitProperty_ScheduleStartTimeStamp, 
									   kAudioUnitScope_Global, 
									   0, &startTime, sizeof(startTime)));
	
	verify_noerr (AudioUnitSetProperty(	fileUnit,
									   kAudioUnitProperty_ScheduleStartTimeStamp, 
									   kAudioUnitScope_Global, 
									   0, &startTime, sizeof(startTime)));									
	
}


/** loadAudioFile
 Reads the file into memory and prepares for playback. */
- (void) loadAudioFile:(NSString *)inAudioFileName {
	FSRef destFSRef;
	UInt8 *pathName = (UInt8 *)[inAudioFileName UTF8String];
	
	verify_noerr (FSPathMakeRef(pathName, &destFSRef, NULL));
	if(fileId) {
		verify_noerr (AudioFileClose(fileId));
		filePosition = 0;
	}
	verify_noerr (AudioFileOpen(&destFSRef, fsRdPerm, 0, &fileId));
	verify_noerr (AudioUnitSetProperty(	fileUnit, 
									   kAudioUnitProperty_ScheduledFileIDs,
									   kAudioUnitScope_Global,
									   0, &fileId, sizeof(fileId) ));
}


#pragma mark -
#pragma mark Interaction


/** buildAudioUnitList
 Finds all of the AudioUnits that are installed on the computer and builds up
 allAudioUnits[] to store them and populates audioUnitPopup. */
- (void) buildAudioUnitList {
	delete [] allAudioUnits;

	CAComponentDescription desc = CAComponentDescription(kAudioUnitType_Effect);
	int count = desc.Count();
	CAComponent *last = NULL;
	
	allAudioUnits = new CAComponent[count];
	for (int i = 0; i < count; ++i) {
		CAComponent temp = CAComponent(desc, last);
		last = &temp;
		allAudioUnits[i] = temp;
		[audioUnitPopup addItemWithTitle:(NSString *)(temp.GetAUName())];
	}
}


/** selectAudioUnit
 Show the UI for the audio unit that is selected. */
- (IBAction) selectAudioUnit :(id)sender {
	int i = [audioUnitBrowser selectedRowInColumn:0];
	[self showAudioUnit: activeUnits[path[i]]];
}


/** selectFile
 Show dialog and open file if a valid one is selected. */
- (IBAction) selectFile :(id)sender {
	// Create the file chooser
	NSOpenPanel * openDialog = [NSOpenPanel openPanel];
	[openDialog setCanChooseFiles:YES];
	[openDialog setCanChooseDirectories: NO];
	[openDialog setAllowsMultipleSelection: NO];	
	[openDialog setAllowedFileTypes:[NSArray arrayWithObjects:@"mp3",@"aiff",@"wav",@"sd2",@"aifc",@"aac",nil]];

	// Display the dialog.  If the OK button was pressed, process the files.
	if ( [openDialog runModal] == NSFileHandlingPanelOKButton ) {
		// TODO ensure only a valid format
		
		
		fileName = [[(NSURL*)[[openDialog URLs] objectAtIndex:0] path] retain];
		[songName setStringValue:[fileName lastPathComponent]];
		
		[self stopMusic:self];
		[self loadAudioFile:fileName];
		[playButton setEnabled: YES];
		[stopButton setEnabled: YES];
	}
}


/** stopMusic
 Terminates file playback and resets position to the beginning of the file. */
- (IBAction) stopMusic: (id)sender {
	AudioUnitReset(fileUnit, kAudioUnitScope_Global, 0);
 	filePosition = 0;
	playing = NO;
	[playButton setState: NSOffState];
}


/** playPause
 Toggles between playing and pausing the file. When paused, the player remembers
 the current position so it can be resumed from there later. */
- (IBAction) playPause:(id)sender {
	playing = !playing;
	[playButton setState: playing ? NSOnState : NSOffState];
	if (playing) {
		// Start/resume playback
		[self prepareFileAudioUnit];
	} else {
		// Record the current position
		AudioTimeStamp ts;
		UInt32 size = sizeof(ts);
		AudioUnitGetProperty(fileUnit, kAudioUnitProperty_CurrentPlayTime, kAudioUnitScope_Global, 0, &ts, &size);
		filePosition = ts.mSampleTime;
		
		// Stop music playback
		AudioUnitReset(fileUnit, kAudioUnitScope_Global, 0); 
	}
}


#pragma mark -
#pragma mark Delegate Methods

// Standard Window Delegates
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)inSender {
	return YES;
}

- (void) windowWillClose:(NSNotification *) aNotification {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[scrollView release];
	delete [] allAudioUnits;
	if(fileId)
		verify_noerr(AudioFileClose(fileId));
    [self destroyGraph];
}


// NSBrowser Delegates
- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column {
	return path.size();
}

- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column {
	[cell setLeaf: YES];
	[cell setTitle: activeNames[path[row]]];
}

#pragma mark -

@end
