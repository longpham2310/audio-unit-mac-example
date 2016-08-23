//
//  MacAudioController.m
//  PlayThrough
//
//  Created by Long Pham on 04/08/2016.
//  Copyright © 2016 Tagher. All rights reserved.
//

#import "MacAudioController.h"
#import <AudioToolbox/AudioToolbox.h>

#define kOutputBus 0
#define kInputBus 1
#define SampleRate 44100
#define numberOfChannel 1  // 1 is mono: 2 is stereo

@interface MacAudioController ()

@property (nonatomic) CGFloat bufferLen;
@property (nonatomic) UInt32 sampleRate;
@property (nonatomic) BOOL mute;

@property (nonatomic) NSData *tempData;

@end

void checkStatus(int status){
    if (status) {
        printf("Status not 0! %d\n", status);
    }
}

//static char *FormatError(char *str, OSStatus error)
//{
//    // see if it appears to be a 4-char-code
//    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
//    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
//        str[0] = str[5] = '\'';
//        str[6] = '\0';
//    } else {
//        // no, format it as an integer
//        sprintf(str, "%d", (int)error);
//    }
//    return str;
//}

ExtAudioFileRef destAudioFile;

/**
 This callback is called when new audio data from the microphone is
 available.
 */
static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    
    // Because of the way our audio format (setup below) is chosen:
    // we only need 1 buffer, since it is mono
    // Samples are 16 bits = 2 bytes.
    // 1 frame includes only 1 sample
    MacAudioController *macOsAudio = (__bridge MacAudioController*)inRefCon;
    
    AudioBuffer buffer;
    
    buffer.mNumberChannels = 1;
    buffer.mDataByteSize = inNumberFrames * sizeof(UInt16);
    buffer.mData = malloc( inNumberFrames * sizeof(UInt16));
    memset(buffer.mData,0,sizeof(UInt16)*inNumberFrames);
    // Put buffer in a AudioBufferList
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;
    
    OSStatus err = AudioUnitRender([macOsAudio audioUnit],
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &bufferList);
    checkStatus(err);
    
    // Now, we have the samples we just read sitting in buffers in bufferList
    // Process the new data
    
    //Test
    [macOsAudio convertAudioBufferListToData:&bufferList];
//    [macOsAudio processAudio:&bufferList];
    
    // WRITE THE DATA TO FILE
    if (!destAudioFile) {
        AudioStreamBasicDescription audioFormat;
        audioFormat.mSampleRate			= SampleRate;
        audioFormat.mFormatID			= kAudioFormatLinearPCM;
        audioFormat.mFormatFlags        = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        audioFormat.mFramesPerPacket	= 1;
        audioFormat.mChannelsPerFrame	= numberOfChannel;
        audioFormat.mBitsPerChannel		= 8 * sizeof(UInt16);
        audioFormat.mBytesPerPacket		= sizeof(UInt16);
        audioFormat.mBytesPerFrame		= sizeof(UInt16);
        
        CFStringRef fPath;
        fPath = CFStringCreateWithCString(kCFAllocatorDefault,
                                          "Record.aiff",
                                          NSUTF8StringEncoding);
        
        NSURL * destURL = [NSURL fileURLWithPath:(__bridge NSString * _Nonnull)(fPath)];
        
        ExtAudioFileCreateWithURL( (__bridge CFURLRef)destURL, kAudioFileAIFFType, &audioFormat, NULL, kAudioFileFlags_EraseFile, &destAudioFile );
    }
    
    ExtAudioFileWriteAsync(destAudioFile,
                           inNumberFrames,
                           &bufferList);
    
    // release the malloc'ed data in the buffer we created earlier
    free(bufferList.mBuffers[0].mData);
    
    return noErr;
}

/**
 This callback is called when the audioUnit needs new data to play through the
 speakers. If you don't have any, just don't write anything in the buffers
 */
static OSStatus playbackCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberFrames,
                                 AudioBufferList *ioData) {
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
    MacAudioController *iosAudio = (__bridge MacAudioController*)inRefCon;
    NSData *data = [iosAudio audioDataPCMLen:ioData->mBuffers[0].mDataByteSize];
    
    data = iosAudio.tempData;
    NSUInteger len = data.length;
    
    for (int i=0; i < ioData->mNumberBuffers; i++) { // in practice we will only ever have 1 buffer, since audio format is mono
        AudioBuffer buffer = ioData->mBuffers[i];
        
        //		NSLog(@"  Buffer %d has %d channels and wants %d bytes of data.", i, buffer.mNumberChannels, buffer.mDataByteSize);
        
        // copy temporary buffer data to output buffer
        NSUInteger size = min(buffer.mDataByteSize, len); // dont copy more data then we have, or then fits
        memcpy(buffer.mData, data.bytes, size);
        buffer.mDataByteSize = (UInt32)size; // indicate how much data we wrote in the buffer
        
        // uncomment to hear random noise
//         UInt16 *frameBuffer = buffer.mData;
//         for (int j = 0; j < inNumberFrames; j++) {
//         frameBuffer[j] = rand();
//         }
        
    }
    
    return noErr;
}

@implementation MacAudioController

@synthesize audioUnit;

/**
 Initialize the audioUnit and allocate our own temporary buffer.
 The temporary buffer will hold the latest data coming in from the microphone,
 and will be copied to the output when this is requested.
 */
- (id) init {
    self = [super init];
    
    [self setupAudioDevice];
    [self setupEnableIO];
    [self setupMicInput];
    [self setupInputFormat];
    [self setupInputCallback];
    [self setupRenderCallback];
    
    OSStatus err = AudioUnitInitialize(audioUnit);
    checkStatus(err);
    
    return self;
}

/**
 Start the audioUnit. This means data will be provided from
 the microphone, and requested for feeding to the speakers, by
 use of the provided callbacks.
 */
- (void) start {
    OSStatus status = AudioOutputUnitStart(audioUnit);
    checkStatus(status);
}

#pragma mark - Setup audio device
- (OSStatus) setupAudioDevice { // It's oks
    AudioComponentDescription desc;
    AudioComponent comp;
    
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_HALOutput;//kAudioUnitSubType_VoiceProcessingIO;
    
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    comp = AudioComponentFindNext(NULL, &desc);
    if (comp == NULL)
    {
        return -1;
    }
    
    OSStatus err = AudioComponentInstanceNew(comp, &audioUnit);
    checkStatus(err);
    
    return err;
}

//https://developer.apple.com/library/prerelease/content/technotes/tn2091/_index.html
- (OSStatus) setupEnableIO { // It's ok
    UInt32 enableIO;
    
    //When using AudioUnitSetProperty the 4th parameter in the method
    //refer to an AudioUnitElement. When using an AudioOutputUnit
    //the input element will be '1' and the output element will be '0'.
    
    
    enableIO = 1;
    OSStatus err = AudioUnitSetProperty(audioUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         kInputBus, // input element
                         &enableIO,
                         sizeof(enableIO));
    
    checkStatus(err);
    
    enableIO = 0;
    err = AudioUnitSetProperty(audioUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output,
                         kOutputBus,   //output element
                         &enableIO,
                         sizeof(enableIO));
    checkStatus(err);
    
    return err;
}

- (OSStatus) setupMicInput { // It's ok
    AudioObjectPropertyAddress addr;
    UInt32 size = sizeof(AudioDeviceID);
    AudioDeviceID deviceID = 0;
    
    addr.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    addr.mScope = kAudioObjectPropertyScopeGlobal;
    addr.mElement = kAudioObjectPropertyElementMaster;

    OSStatus err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &deviceID);
    checkStatus(err);
    
    if (err == noErr) {
        err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, size);
    }
    
    checkStatus(err);
    int m_valueCount = deviceID / sizeof(AudioValueRange) ;
    NSLog(@"Available %d Sample Rates\n",m_valueCount);
    
    NSLog(@"DeviceName: %@",[self deviceName:deviceID]);
    NSLog(@"BufferSize: %d",[self bufferSize:deviceID]);
    
    return err;
}

- (OSStatus)setupInputFormat {
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate			= SampleRate;
    audioFormat.mFormatID			= kAudioFormatLinearPCM;
    audioFormat.mFormatFlags        = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket	= 1;
    audioFormat.mChannelsPerFrame	= numberOfChannel;
    audioFormat.mBitsPerChannel		= 8 * sizeof(UInt16);
    audioFormat.mBytesPerPacket		= sizeof(UInt16);
    audioFormat.mBytesPerFrame		= sizeof(UInt16);
    
    UInt32 size = sizeof(AudioStreamBasicDescription);
    
    // Apply format
    OSStatus err = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &audioFormat,
                                  size);
    checkStatus(err);
    
    err = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  1,
                                  &audioFormat,
                                  size);
    checkStatus(err);
    
    return err;
}

- (OSStatus)setupInputCallback {
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = recordingCallback;
    callbackStruct.inputProcRefCon = (__bridge void * _Nullable)(self);
    
    UInt32 size = sizeof(AURenderCallbackStruct);
    OSStatus err = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  0,
                                  &callbackStruct,
                                  size);
    checkStatus(err);
    
    return err;
}

- (OSStatus)setupRenderCallback {
    // Set output callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = playbackCallback;
    callbackStruct.inputProcRefCon = (__bridge void * _Nullable)(self);
    
    UInt32 size = sizeof(AURenderCallbackStruct);
    OSStatus err = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  1,
                                  &callbackStruct,
                                  size);
    checkStatus(err);
    
    return err;
}

#pragma mark - Helper Methods
-(NSString *)deviceName:(AudioDeviceID)devID
{
    // Check name
    AudioObjectPropertyAddress address;
    
    address.mSelector = kAudioObjectPropertyName;
    address.mScope = kAudioObjectPropertyScopeGlobal;
    address.mElement = kAudioObjectPropertyElementMaster;

    CFStringRef name;
    UInt32 stringsize = sizeof(CFStringRef);
    
    AudioObjectGetPropertyData(devID, &address, 0, nil, &stringsize, &name);
    
    return (__bridge NSString *)(name);
    
}

-(UInt32)bufferSize:(AudioDeviceID)devID
{
    // Check buffer size
    AudioObjectPropertyAddress address;
    
    address.mSelector = kAudioDevicePropertyBufferFrameSize;
    address.mScope = kAudioObjectPropertyScopeGlobal;
    address.mElement = kAudioObjectPropertyElementMaster;
    
    UInt32 buf = 0;
    UInt32 bufSize = sizeof(UInt32);
    
    AudioObjectGetPropertyData(devID, &address, 0, nil, &bufSize, &buf);
    
    return buf;
}

/**
 Stop the audioUnit
 */
- (void) stop {
    OSStatus status = AudioOutputUnitStop(audioUnit);
    checkStatus(status);
    
    // Stop write to file
    ExtAudioFileDispose(destAudioFile);
    destAudioFile = NULL;
}

-(BOOL)microphoneInput:(BOOL)enable;
{
    self.mute = !enable;
    UInt32 enableInput = (enable)? 1 : 0;
    OSStatus status = AudioUnitSetProperty(
                                           audioUnit,//our I/O unit
                                           kAudioOutputUnitProperty_EnableIO, //property we are changing
                                           kAudioUnitScope_Input,
                                           1, //#define kInputBus 1
                                           &enableInput,
                                           sizeof (enableInput)
                                           );
    return (status == noErr);
}

/**
 Change this funtion to decide what is done with incoming
 audio data from the microphone.
 Right now we copy it to our own temporary buffer.
 */
- (void) processAudio: (AudioBufferList*) bufferList{
    AudioBuffer sourceBuffer = bufferList->mBuffers[0];
    
    // fix tempBuffer size if it's the wrong size
    if (tempBuffer.mDataByteSize != sourceBuffer.mDataByteSize) {
        free(tempBuffer.mData);
        tempBuffer.mDataByteSize = sourceBuffer.mDataByteSize;
        tempBuffer.mData = malloc(sourceBuffer.mDataByteSize);
    }
    
    // copy incoming audio data to temporary buffer
    if (self.mute) {
        memset(tempBuffer.mData, 0xFF, bufferList->mBuffers[0].mDataByteSize);
    }else {
        memcpy(tempBuffer.mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    }
    
    if (sourceBuffer.mDataByteSize > 0) {
        [self.delegate processBuffer:&(tempBuffer)];
    }
}

-(NSData*)audioDataPCMLen:(UInt32)pcmlen
{
    UInt32 len = self.sampleRate * self.bufferLen;
    return [NSData dataWithBytes:tempBuffer.mData length:tempBuffer.mDataByteSize];
    return [self.delegate pollDataWithExpectedLen:pcmlen frame:len];
}

/**
 Clean up.
 */
- (void) dealloc {
    AudioComponentInstanceDispose(audioUnit);
}

-(NSData *)convertAudioBufferListToData: (AudioBufferList*) audioBufferList
{
    AudioBuffer buffer = audioBufferList->mBuffers[0];
    NSData *d = [NSData dataWithBytes:buffer.mData length:buffer.mDataByteSize];
    int sum=0;
    self.tempData = d;
    NSLog(@"Datasize of buffer: %ld",d.length);
    for (int i = 0; i < buffer.mDataByteSize; i=i+2) {
        NSLog(@"%d",(CFSwapInt16BigToHost(((short*)buffer.mData)[i])));
        sum=sum+abs(CFSwapInt16BigToHost(((short*)buffer.mData)[i]));
    }
    NSLog(@"Volume: %d",sum);
    return d;
    
//    return data;
    
    // copy incoming audio data to the audio buffer (no need since we are not using playback)
    //memcpy(inAudioBuffer.mData, audioBufferList->mBuffers[0].mData, audioBufferList->mBuffers[0].mDataByteSize);
}

@end
