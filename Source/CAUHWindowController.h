
#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>

#import <Cocoa/Cocoa.h>

#import "AudioFileReceiver_Protocol.h"

@class AudioFileListView;
class CAComponent;

@interface HostingWindowController : NSWindowController <AudioFileReceiver>
{
    // IB: AU Selection
   // IBOutlet NSMatrix *				uiAUTypeMatrix;
    IBOutlet NSButton *				uiAudioFileButton;
    IBOutlet NSPopUpButton *		uiAUPopUpButton;
    IBOutlet NSBox *				uiAUViewContainer;
    
    // IB: Audio Transport
    IBOutlet NSButton *				uiPlayStopButton;
    IBOutlet AudioFileListView *	uiAudioFileTableView;
    IBOutlet NSTextField *			uiAudioFileNowPlayingName;
    
    // Post-nib view manufacturing
    NSScrollView *					mScrollView;
    
    // AU Tracking
    OSType							mComponentHostType;
	CAComponent *					mAUList;
    NSMutableArray *				mAudioFileList;
    
    // AudioFile / AUGraph members
    //AudioFilePlayID					mAFPID;
	AudioFileID						mAFID;
	AUGraph							mGraph;
	AUNode							mFileNode, mTargetNode, mOutputNode;
	AudioUnit						mFileUnit, mTargetUnit, mOutputUnit;

}

- (void)stopGraph;

#pragma mark IB Actions
- (IBAction)iaAUTypeChanged:(id)sender;
- (IBAction)iaAUPopUpButtonPressed:(id)sender;
- (IBAction)iaPlayStopButtonPressed:(id)sender;

@end
