//
//  AudioFileReceiver_Protocol.h
//  host
//
//  Created by Doug Hyde on 10/15/09.
//  Copyright 2009 Washington University in St. Louis. All rights reserved.
//


#import <Cocoa/Cocoa.h>

@protocol AudioFileReceiver
- (void)addLinkToFiles:(NSArray *)inFiles;
@end

