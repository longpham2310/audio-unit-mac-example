//
//  ViewController.m
//  Demo
//
//  Created by Long Pham on 04/08/2016.
//  Copyright © 2016 Tagher. All rights reserved.
//

#import "ViewController.h"
#import "MacAudioController.h"

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];

    self.audioController = [MacAudioController new];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


- (IBAction)start:(id)sender {
    [self.audioController start];
}

- (IBAction)stop:(id)sender {
    [self.audioController stop];
}

@end
