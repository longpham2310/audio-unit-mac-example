//
//  MacAudioController.h
//  PlayThrough
//
//  Created by Long Pham on 04/08/2016.
//  Copyright © 2016 Tagher. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#ifndef max
#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

#ifndef min
#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

@protocol MacAudioControllerDelegate <NSObject>

-(void)processBuffer:(AudioBuffer*)bufferList;
-(NSData*)pollDataWithExpectedLen:(UInt32)len frame:(UInt32)frame;

@end

@interface MacAudioController : NSObject {
    AudioComponentInstance audioUnit;
    AudioBuffer tempBuffer; // this will hold the latest data from the microphone
}

@property (readonly) AudioComponentInstance audioUnit;
@property (nonatomic, weak) id<MacAudioControllerDelegate> delegate;

- (void) start;
- (void) stop;
- (BOOL)microphoneInput:(BOOL)enable;
- (void) processAudio: (AudioBufferList*) bufferList;
- (NSData*)audioDataPCMLen:(UInt32)pcmlen;

-(NSData *)convertAudioBufferListToData: (AudioBufferList*) audioBufferList;
@end
