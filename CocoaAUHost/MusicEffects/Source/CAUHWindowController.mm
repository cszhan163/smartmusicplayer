
#import <CoreAudioKit/CoreAudioKit.h>
#import <AudioUnit/AUCocoaUIView.h>

#include "CAComponent.h"
#include "CAComponentDescription.h"
#include "CAStreamBasicDescription.h"

#import "CAUHWindowController.h"

#import "AudioFileListView.h"


void AudioFileNotificationHandler (void *inRefCon, OSStatus inStatus)
{
    HostingWindowController *SELF = (HostingWindowController *)inRefCon;
    [SELF performSelectorOnMainThread:@selector(iaPlayStopButtonPressed:) withObject:SELF waitUntilDone:NO];
}

int componentCountForAUType(OSType inAUType)
{
	CAComponentDescription desc = CAComponentDescription(inAUType);
	return desc.Count();
}

void getComponentsForAUType(OSType inAUType, CAComponent *ioCompBuffer, int count)
{
	CAComponentDescription desc = CAComponentDescription(inAUType);
	CAComponent *last = NULL;
	
	for (int i = 0; i < count; ++i) {
		ioCompBuffer[i] = CAComponent(desc, last);
		last = &(ioCompBuffer[i]);
	}
}

@implementation HostingWindowController
+ (BOOL)plugInClassIsValid:(Class) pluginClass
{
	if ([pluginClass conformsToProtocol:@protocol(AUCocoaUIBase)]) {
		if ([pluginClass instancesRespondToSelector:@selector(interfaceVersion)] &&
			[pluginClass instancesRespondToSelector:@selector(uiViewForAudioUnit:withSize:)]) {
			return YES;
		}
	}
	
    return NO;
}

- (void)showCocoaViewForAU:(AudioUnit)inAU
{
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

- (void)synchronizePlayStopButton
{
    if (mComponentHostType == kAudioUnitType_Effect) {
        [uiPlayStopButton setEnabled:[mAudioFileList count] > 0];
    } else {
        [uiPlayStopButton setEnabled:YES];
    }
}

- (void)synchronizeForNewAUType {
    mComponentHostType = kAudioUnitType_Effect;
    
    // [B] sync with new AUType
    //   [1] get new AUList
	if (mAUList != NULL) {
		free (mAUList);
		mAUList = NULL;
	}
	
	int componentCount = componentCountForAUType(mComponentHostType);
	UInt32 dataByteSize = componentCount * sizeof(CAComponent);
	mAUList = static_cast<CAComponent *>(malloc(dataByteSize));
	memset (mAUList, 0, dataByteSize);
	getComponentsForAUType(mComponentHostType, mAUList, componentCount);
	
	//   [2] populate AUPopUp with new list
    [uiAUPopUpButton removeAllItems];
	
	for (int i = 0; i < componentCount; ++i) {
		[uiAUPopUpButton addItemWithTitle:(NSString *)(mAUList[i].GetAUName())];
	}
    
    //   [3] enable AudioFileDrawerToggle button for effects
    if (mComponentHostType == kAudioUnitType_Effect) {
        [uiAudioFileButton setEnabled:YES];
    } else {
        [uiAudioFileButton setEnabled:NO];
        [(NSDrawer *)[[[self window] drawers] objectAtIndex:0] close];
    }
    
    //   [4] other UI
    [self synchronizePlayStopButton];
    
    //   [5] select top-of-list AU & show its UI
    [self iaAUPopUpButtonPressed:self];  
}

- (void)addLinkToFiles:(NSArray *)inFiles
{
    [mAudioFileList addObjectsFromArray:inFiles];
    [self synchronizePlayStopButton];
    [uiAudioFileTableView reloadData];
}

- (void)createGraph
{
	verify_noerr (NewAUGraph(&mGraph));
	
	CAComponentDescription desc = CAComponentDescription (	kAudioUnitType_Output,
															kAudioUnitSubType_DefaultOutput,
															kAudioUnitManufacturer_Apple	);
    
	verify_noerr (AUGraphAddNode(mGraph, &desc, &mOutputNode));
	
	desc = CAComponentDescription (	kAudioUnitType_Generator,
									kAudioUnitSubType_AudioFilePlayer,
									kAudioUnitManufacturer_Apple	);
    
	verify_noerr (AUGraphAddNode(mGraph, &desc, &mFileNode));

	verify_noerr (AUGraphOpen(mGraph));
	
    verify_noerr (AUGraphNodeInfo(mGraph, mFileNode, NULL, &mFileUnit));
    verify_noerr (AUGraphNodeInfo(mGraph, mOutputNode, NULL, &mOutputUnit));
}

void filePlayCompletionProc	(	void *userData, 
								ScheduledAudioFileRegion *fileRegion, 
								OSStatus result)
{
	printf("File completed!\n");
	HostingWindowController* This = (HostingWindowController*)userData;
	[This stopGraph];
}

- (void)prepareFileAU
{	
	
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
	verify_noerr (AudioUnitSetProperty(	mFileUnit, 
										kAudioUnitProperty_ScheduledFileRegion, 
										kAudioUnitScope_Global, 
										0,
										&rgn, 
										sizeof(rgn)));
	
	// prime the fp AU with default values
	UInt32 defaultVal = 0;
	verify_noerr (AudioUnitSetProperty(	mFileUnit,
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
	verify_noerr (AudioUnitSetProperty(	mFileUnit,
										kAudioUnitProperty_ScheduleStartTimeStamp, 
										kAudioUnitScope_Global, 
										0,
										&startTime, 
										sizeof(startTime)));
										
	verify_noerr (AudioUnitSetProperty(	mFileUnit,
										kAudioUnitProperty_ScheduleStartTimeStamp, 
										kAudioUnitScope_Global, 
										0,
										&startTime, 
										sizeof(startTime)));									

}

- (void)startGraph
{
    verify_noerr (AUGraphConnectNodeInput (mGraph, mTargetNode, 0, mOutputNode, 0));
	// if the unit is an effect, connect the file player to its input
	if (mComponentHostType == kAudioUnitType_Effect)
	    verify_noerr (AUGraphConnectNodeInput (mGraph, mFileNode, 0, mTargetNode, 0));
    
	verify_noerr (AUGraphUpdate (mGraph, NULL) == noErr);
    verify_noerr (AUGraphInitialize(mGraph) == noErr);
	
	if (mComponentHostType == kAudioUnitType_Effect)
		[self prepareFileAU];
		
    verify_noerr (AUGraphStart(mGraph) == noErr);
}

- (void)stopGraph
{
	verify_noerr (AUGraphStop(mGraph));
	verify_noerr (AUGraphUninitialize(mGraph));
	verify_noerr (AUGraphClearConnections (mGraph));
	verify_noerr (AUGraphUpdate (mGraph, NULL));
	if(mAFID)
		verify_noerr (AudioFileClose(mAFID));
}

- (void)destroyGraph
{
	// stop graph if necessary
    Boolean isRunning = FALSE;
	verify_noerr (AUGraphIsRunning(mGraph, &isRunning));
	if (isRunning)
		[self stopGraph];
	
	// close and destroy
	verify_noerr (AUGraphClose(mGraph));
	verify_noerr (DisposeAUGraph(mGraph));
}

- (void)loadAudioFile:(NSString *)inAudioFileName
{
	FSRef destFSRef;
	UInt8 *pathName = (UInt8 *)[inAudioFileName UTF8String];

	verify_noerr (FSPathMakeRef(pathName, &destFSRef, NULL));
	verify_noerr (AudioFileOpen(&destFSRef, fsRdPerm, 0, &mAFID));

	verify_noerr (AudioUnitSetProperty(	mFileUnit, 
										kAudioUnitProperty_ScheduledFileIDs,
										kAudioUnitScope_Global,
										0,
										&mAFID,
										sizeof(mAFID) ));
}

- (void)awakeFromNib
{
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
    [self synchronizeForNewAUType];
    
	// make this the app. delegate
	[NSApp setDelegate:self];
	
	[[self window] setDelegate: self];
}

-(void)cleanup {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
	if (mAUList != NULL) {
		free(mAUList);
		mAUList = NULL;
	}
	
    [mAudioFileList release];
    
	if(mAFID)
		verify_noerr(AudioFileClose(mAFID));
    
    [self destroyGraph];
}

- (IBAction)iaAUTypeChanged:(id)sender
{
    [self synchronizeForNewAUType];
}

- (IBAction)iaAUPopUpButtonPressed:(id)sender
{
    // replace effect AU in chain
	int index = [uiAUPopUpButton indexOfSelectedItem];
	AudioComponentDescription desc = mAUList[index].Desc();//[[mAUList objectAtIndex:index] componentDescription];
	
	if (mTargetNode) {
			// remove the old view first before closing the AU
		[[mScrollView documentView] removeFromSuperview];
		verify_noerr (AUGraphRemoveNode(mGraph, mTargetNode));
    }
	
    verify_noerr (AUGraphAddNode(mGraph, &desc, &mTargetNode));
	verify_noerr (AUGraphNodeInfo(mGraph, mTargetNode, NULL, &mTargetUnit));
    verify_noerr (AUGraphUpdate (mGraph, NULL));
	
	[self showCocoaViewForAU:mTargetUnit];
}

- (IBAction)iaPlayStopButtonPressed:(id)sender
{
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
		
        [uiAUPopUpButton setEnabled:YES];
        return;
    }
    
	// [2] otherwise start the AUGraph
    // load file
    if (mComponentHostType == kAudioUnitType_Effect) {
		int selectedRow = [uiAudioFileTableView selectedRow];
		if ( (selectedRow < 0) || ([mAudioFileList count] == 0) ) return;	// no file selected
		
		NSString *audioFileName = (NSString *)[mAudioFileList objectAtIndex:selectedRow];
		[self loadAudioFile:audioFileName];
		
        // set filename in UI
        [uiAudioFileNowPlayingName setStringValue:[audioFileName lastPathComponent]];
    }
    [uiAUPopUpButton setEnabled:NO];
    
	[self startGraph];
}

- (int)numberOfRowsInTableView:(NSTableView *)inTableView
{
    int count = [mAudioFileList count];
    return (count > 0) ? count : 1;
}

- (id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)inTableColumn row:(int)inRow
{
    int count = [mAudioFileList count];
    return (count > 0) ?	[(NSString *)[mAudioFileList objectAtIndex:inRow] lastPathComponent] :
                            @"< drag audio files here >";
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)inSender
{
	return YES;
}

- (void) windowWillClose:(NSNotification *) aNotification {
	[self cleanup];
}

@end
