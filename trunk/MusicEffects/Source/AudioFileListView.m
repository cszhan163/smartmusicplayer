
#import "AudioFileReceiver_Protocol.h"

#import "AudioFileListView.h"


@interface NSView (DragHighlight)
	- (void)drawDragHighlightOutside:(BOOL)anOutside;
	- (void)clearDragHighlightOutside;
@end

@implementation NSView (DragHighlight)

- (void)drawDragHighlightOutside:(BOOL)anOutside
{
	NSView  		* theDrawView;
	
	theDrawView = ( anOutside ) ? [self superview] : self;
	
	if( theDrawView != nil )
	{
		NSRect  				theRect, winRect;
		
		theRect = ( anOutside ) ? NSInsetRect([theDrawView frame], -3, 
-3 ) : [theDrawView bounds];
		winRect = theRect;
		winRect = [theDrawView convertRect: theRect toView: nil];
		[[self window] cacheImageInRect:winRect];
		
		[theDrawView lockFocus];
		
		[[NSColor selectedControlColor] set];
		NSFrameRectWithWidthUsingOperation( theRect, 3, NSCompositeSourceOver );
		[[NSGraphicsContext currentContext] flushGraphics];
		
		[theDrawView unlockFocus];
	}
}

- (void)clearDragHighlightOutside
{
	[[self window] restoreCachedImage];
	[[self window] flushWindow];
}

@end

@implementation AudioFileListView

- (void)awakeFromNib {
	[self registerForDraggedTypes:[NSArray arrayWithObjects:
			NSFilenamesPboardType, nil]];
}

- (id)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		mCurrentDragOp = NSDragOperationNone;
   }
	return self;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
	NSPasteboard *pboard;
	NSDragOperation sourceDragMask;

	sourceDragMask = [sender draggingSourceOperationMask];
	pboard = [sender draggingPasteboard];

	if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
		if (sourceDragMask & NSDragOperationLink) {
			[self drawDragHighlightOutside:NO];
			return mCurrentDragOp = NSDragOperationLink;
		}
	}
	return mCurrentDragOp = NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
	[self clearDragHighlightOutside];
	mCurrentDragOp = NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
	return mCurrentDragOp;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
	return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
	NSPasteboard *pboard;
	NSDragOperation sourceDragMask;

	[self clearDragHighlightOutside];
	sourceDragMask = [sender draggingSourceOperationMask];
	pboard = [sender draggingPasteboard];

	if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
		NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];

		// Depending on the dragging source and modifier keys,
		// the file data may be copied or linked
		if (sourceDragMask & NSDragOperationLink) {
			id<AudioFileReceiver> fileReceiver = (id<AudioFileReceiver>)[self dataSource];
			[fileReceiver addLinkToFiles:files];
		}
	}
	return YES;
}

@end
