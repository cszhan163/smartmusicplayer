
#import <CoreAudioKit/CoreAudioKit.h>
#import <AudioUnit/AUCocoaUIView.h>

#include "CAComponent.h"
#include "CAComponentDescription.h"
#include "CAStreamBasicDescription.h"

#import "WindowController.h"
#import "AudioFileListView.h"


void AudioFileNotificationHandler (void *inRefCon, OSStatus inStatus) {
    HostingWindowController *SELF = (HostingWindowController *)inRefCon;
    [SELF performSelectorOnMainThread:@selector(iaPlayStopButtonPressed:) withObject:SELF waitUntilDone:NO];
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

- (void)awakeFromNib {
    mAudioFileList = [[NSMutableArray alloc] init];
	numActiveUnits = 0;
    
    // create scroll-view
    NSRect frameRect = [[uiAUViewContainer contentView] frame];
    mScrollView = [[[NSScrollView alloc] initWithFrame:frameRect] autorelease];
    [mScrollView setDrawsBackground:NO];
    [mScrollView setHasHorizontalScroller:YES];
    [mScrollView setHasVerticalScroller:YES];
    [uiAUViewContainer setContentView:mScrollView];
    
    // dispatched setup
	[self createGraph];
	[self buildAudioUnitList];
	[audioUnitBrowser setDoubleAction: @selector(handleDoubleClick:)];
    
	// make this the app. delegate
	[NSApp setDelegate:self];
}



-(void)cleanup {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	
    [mAudioFileList release];
	delete [] allAudioUnits;
    
	if(mAFID)
		verify_noerr(AudioFileClose(mAFID));
    
    [self destroyGraph];
}


#pragma mark -
#pragma mark Audio Graph

- (void)createGraph {
	verify_noerr (NewAUGraph(&mGraph));
	
	CAComponentDescription desc = CAComponentDescription (	kAudioUnitType_Output,
														  kAudioUnitSubType_DefaultOutput,
														  kAudioUnitManufacturer_Apple	);
	verify_noerr (AUGraphAddNode(mGraph, &desc, &mOutputNode));
	
	desc = CAComponentDescription (	kAudioUnitType_Generator,
								   kAudioUnitSubType_AudioFilePlayer,
								   kAudioUnitManufacturer_Apple	);
	verify_noerr (AUGraphAddNode(mGraph, &desc, &mFileNode));
	
	desc = CAComponentDescription (	kAudioUnitType_Mixer,
								   kAudioUnitSubType_StereoMixer,
								   kAudioUnitManufacturer_Apple	);
	verify_noerr (AUGraphAddNode(mGraph, &desc, &mixerNode));
	
	verify_noerr (AUGraphOpen(mGraph));
    verify_noerr (AUGraphNodeInfo(mGraph, mFileNode, NULL, &mFileUnit));
    verify_noerr (AUGraphNodeInfo(mGraph, mOutputNode, NULL, &mOutputUnit));
	verify_noerr (AUGraphNodeInfo(mGraph, mixerNode, NULL, &mixerUnit));
}


- (void)startGraph {
    AUGraphConnectNodeInput (mGraph, mixerNode, 0, mOutputNode, 0);
	AUGraphConnectNodeInput (mGraph, mFileNode, 0, mixerNode, 0);
	
	AUGraphUpdate (mGraph, NULL);
	CAShow(mGraph);
	
    verify_noerr (AUGraphInitialize(mGraph) == noErr);
	
	[self prepareFileAudioUnit];
	
    verify_noerr (AUGraphStart(mGraph) == noErr);
}


- (void)updateGraph {

	int i = numActiveUnits - 1;
	if (numActiveUnits == 0) {
		verify_noerr (AUGraphConnectNodeInput (mGraph, mFileNode, 0, mixerNode, 0));
	} else if (numActiveUnits == 1) {
		verify_noerr (AUGraphConnectNodeInput (mGraph, activeNodes[0], 0, mixerNode, 0));
		verify_noerr (AUGraphConnectNodeInput (mGraph, mFileNode, 0, activeNodes[0], 0));
	} else {
		verify_noerr (AUGraphDisconnectNodeInput(mGraph, mixerNode, 0));
		verify_noerr (AUGraphConnectNodeInput (mGraph, activeNodes[i], 0, mixerNode, 0));
		verify_noerr (AUGraphConnectNodeInput (mGraph, activeNodes[i-1], 0, activeNodes[i], 0));
	}
	AUGraphUpdate (mGraph, NULL);
	CAShow(mGraph);

}


- (void)stopGraph {
	verify_noerr (AUGraphStop(mGraph));
	verify_noerr (DisposeAUGraph(mGraph));
	mGraph = 0;
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
#pragma mark Audio Unit


/** showAudioUnit
 Displays the Cocoa view for the specified audio unit in the NSBox. */
- (void) showAudioUnit:(AudioUnit)inAU {
	// get AU's Cocoa view property
    UInt32 						dataSize;
    Boolean 					isWritable;
    AudioUnitCocoaViewInfo *	cocoaViewInfo = NULL;
    UInt32						numberOfClasses;
    
    OSStatus result = AudioUnitGetPropertyInfo(	inAU,
											   kAudioUnitProperty_CocoaUI,
											   kAudioUnitScope_Global, 
											   0, &dataSize, &isWritable );
    
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



- (void)prepareFileAudioUnit {	
	// Calculate the duration
	UInt64 nPackets;
	UInt32 propsize = sizeof(nPackets);
	verify_noerr (AudioFileGetProperty(mAFID, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets));
	
	CAStreamBasicDescription fileFormat;
	propsize = sizeof(CAStreamBasicDescription);
	verify_noerr (AudioFileGetProperty(mAFID, kAudioFilePropertyDataFormat, &propsize, &fileFormat));
	
	ScheduledAudioFileRegion rgn;
	memset (&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
	rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
	rgn.mTimeStamp.mSampleTime = 0;
	rgn.mCompletionProc = NULL;
	rgn.mCompletionProcUserData = NULL;
	rgn.mAudioFile = mAFID;
	rgn.mLoopCount = 1;
	rgn.mStartFrame = 0;
	rgn.mFramesToPlay = UInt32(nPackets * fileFormat.mFramesPerPacket);
	
	// Play entire file
	verify_noerr (AudioUnitSetProperty(	mFileUnit, 
									   kAudioUnitProperty_ScheduledFileRegion, 
									   kAudioUnitScope_Global, 
									   0, &rgn, sizeof(rgn)));
	
	// Set default values
	UInt32 defaultVal = 0;
	verify_noerr (AudioUnitSetProperty(	mFileUnit,
									   kAudioUnitProperty_ScheduledFilePrime, 
									   kAudioUnitScope_Global,
									   0, &defaultVal, sizeof(defaultVal)));
	
	// When to start playing (-1 means next render cycle)
	AudioTimeStamp startTime;
	memset (&startTime, 0, sizeof(startTime));
	startTime.mFlags = kAudioTimeStampSampleTimeValid;
	startTime.mSampleTime = -1;
	verify_noerr (AudioUnitSetProperty(	mFileUnit,
									   kAudioUnitProperty_ScheduleStartTimeStamp, 
									   kAudioUnitScope_Global, 
									   0, &startTime, sizeof(startTime)));
	
	verify_noerr (AudioUnitSetProperty(	mFileUnit,
									   kAudioUnitProperty_ScheduleStartTimeStamp, 
									   kAudioUnitScope_Global, 
									   0, &startTime, sizeof(startTime)));									
	
}



#pragma mark -
#pragma mark Interaction

 

- (void)synchronizePlayStopButton {
    [uiPlayStopButton setEnabled:[mAudioFileList count] > 0];
}


- (void) buildAudioUnitList {
	delete [] allAudioUnits;
	[uiAUPopUpButton removeAllItems];
	
	int count = CAComponentDescription(kAudioUnitType_Effect).Count();
	CAComponentDescription desc = CAComponentDescription(kAudioUnitType_Effect);
	CAComponent *last = NULL;
	
	allAudioUnits = new CAComponent[count];
	for (int i = 0; i < count; ++i) {
		CAComponent temp = CAComponent(desc, last);
		last = &temp;
		allAudioUnits[i] = temp;
		[uiAUPopUpButton addItemWithTitle:(NSString *)(temp.GetAUName())];
	}
	
    //   [3] enable AudioFileDrawerToggle button for effects
	[uiAudioFileButton setEnabled:YES];
	
    [self synchronizePlayStopButton];
    [self addAudioUnit:self]; // Select first AudioUnit & show
}


- (void)addLinkToFiles:(NSArray *)inFiles {
    [mAudioFileList addObjectsFromArray:inFiles];
    [self synchronizePlayStopButton];
    [uiAudioFileTableView reloadData];
}




- (IBAction) addAudioUnit :(id)sender {
	

	int index = [uiAUPopUpButton indexOfSelectedItem];
	AudioComponentDescription desc = allAudioUnits[index].Desc();
	
	int i = numActiveUnits;
	verify_noerr (AUGraphAddNode(mGraph, &desc, &activeNodes[i]));
	verify_noerr (AUGraphNodeInfo(mGraph, activeNodes[i], NULL, &activeUnits[i]));
	verify_noerr (AudioUnitInitialize(activeUnits[i]));
	
	++numActiveUnits;
	[self updateGraph];
	[self showAudioUnit: activeUnits[i]];
	
	activeNames[i] = (NSString*)allAudioUnits[index].GetAUName();
	[audioUnitBrowser reloadColumn:0];
}




#pragma mark -
#pragma mark Playback


- (void) loadAudioFile:(NSString *)inAudioFileName {
	FSRef destFSRef;
	UInt8 *pathName = (UInt8 *)[inAudioFileName UTF8String];
	
	verify_noerr (FSPathMakeRef(pathName, &destFSRef, NULL));
	verify_noerr (AudioFileOpen(&destFSRef, fsRdPerm, 0, &mAFID));
	
	verify_noerr (AudioUnitSetProperty(	mFileUnit, 
									   kAudioUnitProperty_ScheduledFileIDs,
									   kAudioUnitScope_Global,
									   0, &mAFID, sizeof(mAFID) ));
}


- (IBAction) stopMusic: (id)sender {
	AudioUnitReset(mFileUnit, kAudioUnitScope_Global, 0); 	
}




- (IBAction)iaPlayStopButtonPressed:(id)sender {
    if (sender == self) {
        // change button icon manually if this function is called internally
        [uiPlayStopButton setState: NSOnState]; //([uiPlayStopButton state] == NSOffState) ? NSOnState : NSOffState];
    }
    
    Boolean isRunning = FALSE;
	verify_noerr (AUGraphIsRunning(mGraph, &isRunning));
	
	// [1] if the AUGraph is running, stop it
    if (isRunning) {
        // stop graph, update UI & return
		[self stopGraph];
		
        [uiAUPopUpButton setEnabled:YES];
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


#pragma mark -
#pragma mark Delegate



- (int)numberOfRowsInTableView:(NSTableView *)inTableView {
    int count = [mAudioFileList count];
    return (count > 0) ? count : 1;
}


- (id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)inTableColumn row:(int)inRow {
    int count = [mAudioFileList count];
    return (count > 0) ?	[(NSString *)[mAudioFileList objectAtIndex:inRow] lastPathComponent] :
                            @"< drag audio files here >";
}


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)inSender {
	return YES;
}


- (void) windowWillClose:(NSNotification *) aNotification {
	[self cleanup];
}


- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column {
	return numActiveUnits;
}


- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column {
	[cell setLeaf: YES];
	[cell setTitle: activeNames[row]];
}


- (BOOL)browser:(NSBrowser *)browser canDragRowsWithIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column withEvent:(NSEvent *)event {
	return YES;
}
/*
- (NSDragOperation)browser:(NSBrowser *)browser validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger *)row
					column:(NSInteger *)column dropOperation:(NSBrowserDropOperation *)dropOperation {
	
	if ([info draggingSource] == self) {
		NSLog(@"YES");
		return NSBrowserDropOn;
	}
	return NSDragOperationNone;
}*/

/*- (BOOL)browser:(NSBrowser *)browser acceptDrop:(id <NSDraggingInfo>)info atRow:(NSInteger)row column:(NSInteger)column dropOperation:(NSBrowserDropOperation)dropOperation {
	
}*/

- (BOOL)browser:(NSBrowser *)browser writeRowsWithIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column toPasteboard:(NSPasteboard *)pasteboard {
	return YES;
}


- (void)handleDoubleClick: (id)sender {
	int i = [audioUnitBrowser selectedRowInColumn:0];
	[self showAudioUnit: activeUnits[i]];
}


#pragma mark -

@end
