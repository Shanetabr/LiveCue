#import <Cocoa/Cocoa.h>
#import <CoreMIDI/CoreMIDI.h>

@interface LampReceiver : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSTextField *summary;
@property NSTextField *detail;
@property NSPopUpButton *sourcePicker;
@property NSPopUpButton *outputPicker;
@property NSButton *bridgeButton;
@property NSButton *flashButton;
@property NSMutableArray<NSNumber *> *sources;
@property NSMutableArray<NSNumber *> *outputs;
@property MIDIClientRef client;
@property MIDIPortRef inputPort;
@property MIDIPortRef outputPort;
@property MIDIEndpointRef connectedSource;
@property BOOL bridgeEnabled;
@property NSUInteger received;
@property NSUInteger forwarded;
@property NSUInteger lampMessages;
@property UInt8 status;
@property UInt8 data0;
@property int dataCount;
@property NSTimer *flashTimer;
@property BOOL lampOn;
@end

@implementation LampReceiver
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
 NSTextField *field = [NSTextField labelWithString:text]; field.frame = frame;
 field.lineBreakMode = NSLineBreakByWordWrapping; field.maximumNumberOfLines = 0;
 [self.window.contentView addSubview:field]; return field;
}
- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
 NSButton *b = [NSButton buttonWithTitle:title target:self action:action]; b.frame=frame; [self.window.contentView addSubview:b]; return b;
}
- (NSString *)name:(MIDIObjectRef)object {
 CFStringRef name = NULL;
 if (MIDIObjectGetStringProperty(object,kMIDIPropertyDisplayName,&name)!=noErr || !name) return @"Unknown";
 return CFBridgingRelease(name);
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
 self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,700,410) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
 self.window.title=@"WING Lamp MIDI Receiver";
 [self label:@"Run this on the AUDIO MacBook connected to WING by USB.\nReceives Network MIDI and forwards ONLY channel 6, CC 16 to WING." frame:NSMakeRect(20,340,660,50)];
 [self label:@"Network MIDI input:" frame:NSMakeRect(20,300,170,25)];
 self.sourcePicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(200,300,470,27)]; [self.window.contentView addSubview:self.sourcePicker];
 [self label:@"WING USB output:" frame:NSMakeRect(20,260,170,25)];
 self.outputPicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(200,260,470,27)]; [self.window.contentView addSubview:self.outputPicker];
 [self button:@"Refresh ports" frame:NSMakeRect(20,215,130,30) action:@selector(refresh:)];
 self.bridgeButton=[self button:@"Start bridge" frame:NSMakeRect(170,215,150,30) action:@selector(toggleBridge:)];
 self.flashButton=[self button:@"Test USB flashing" frame:NSMakeRect(350,215,170,30) action:@selector(toggleFlash:)];
 [self button:@"Lamp OFF / Stop USB test" frame:NSMakeRect(440,165,230,30) action:@selector(stopFlash:)];
 self.summary=[self label:@"Preparing MIDI…" frame:NSMakeRect(20,120,650,80)];
 self.detail=[self label:@"Nothing received yet." frame:NSMakeRect(20,40,650,75)];
 __weak LampReceiver *weakSelf=self;
 OSStatus status=MIDIClientCreateWithBlock(CFSTR("WING Lamp Receiver"),&_client,^(const MIDINotification *n){});
 if (status==noErr) status=MIDIOutputPortCreate(self.client,CFSTR("WING Lamp Output"),&_outputPort);
 if (status==noErr) status=MIDIInputPortCreateWithBlock(self.client,CFSTR("Network Lamp Input"),&_inputPort,^(const MIDIPacketList *list, void *context){
  const MIDIPacket *packet=&list->packet[0];
  for (UInt32 i=0;i<list->numPackets;i++) {
   NSData *data=[NSData dataWithBytes:packet->data length:packet->length];
   dispatch_async(dispatch_get_main_queue(),^{ [weakSelf receive:data]; });
   packet=MIDIPacketNext(packet);
  }
 });
 if(status!=noErr) self.detail.stringValue=[NSString stringWithFormat:@"MIDI initialization failed: %d",(int)status];
 [self refresh:nil]; [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)refresh:(id)sender {
 if(self.bridgeEnabled) [self toggleBridge:nil];
 self.sources=[NSMutableArray array]; self.outputs=[NSMutableArray array];
 [self.sourcePicker removeAllItems]; [self.outputPicker removeAllItems];
 for(ItemCount i=0;i<MIDIGetNumberOfSources();i++) {
  MIDIEndpointRef endpoint=MIDIGetSource(i); NSString *name=[self name:endpoint];
  if([name rangeOfString:@"Network" options:NSCaseInsensitiveSearch].location!=NSNotFound) { [self.sources addObject:@(endpoint)]; [self.sourcePicker addItemWithTitle:name]; }
 }
 for(ItemCount i=0;i<MIDIGetNumberOfDestinations();i++) {
  MIDIEndpointRef endpoint=MIDIGetDestination(i); NSString *name=[self name:endpoint];
  if([name rangeOfString:@"WING" options:NSCaseInsensitiveSearch].location!=NSNotFound) { [self.outputs addObject:@(endpoint)]; [self.outputPicker addItemWithTitle:name]; }
 }
 for(NSInteger i=0;i<self.outputPicker.numberOfItems;i++) if([self.outputPicker.itemTitles[i] rangeOfString:@"Port 4" options:NSCaseInsensitiveSearch].location!=NSNotFound) [self.outputPicker selectItemAtIndex:i];
 self.summary.stringValue=@"Choose Network Session 1 and WING Port 4, then Start bridge.";
 self.bridgeButton.enabled=self.sources.count>0 && self.outputs.count>0;
 self.flashButton.enabled=self.outputs.count>0;
}
- (MIDIEndpointRef)output { NSInteger index=self.outputPicker.indexOfSelectedItem; return index>=0 && index<self.outputs.count ? self.outputs[index].unsignedIntValue : 0; }
- (OSStatus)sendValue:(UInt8)value {
 MIDIEndpointRef output=[self output]; if(!output) return kMIDIInvalidClient;
 MIDIPacketList list; MIDIPacket *first=MIDIPacketListInit(&list); UInt8 bytes[3]={0xB5,0x10,value};
 MIDIPacketListAdd(&list,sizeof(list),first,0,3,bytes);
 return MIDISend(self.outputPort,output,&list);
}
- (void)toggleBridge:(id)sender {
 if(self.bridgeEnabled) {
  MIDIPortDisconnectSource(self.inputPort,self.connectedSource); self.bridgeEnabled=NO; self.status=0; self.dataCount=0;
  self.bridgeButton.title=@"Start bridge"; self.sourcePicker.enabled=YES; self.outputPicker.enabled=YES;
  self.summary.stringValue=@"Bridge stopped."; return;
 }
 if(self.sources.count==0 || ![self output]) return;
 self.connectedSource=self.sources[self.sourcePicker.indexOfSelectedItem].unsignedIntValue;
 OSStatus result=MIDIPortConnectSource(self.inputPort,self.connectedSource,NULL);
 if(result!=noErr){self.detail.stringValue=[NSString stringWithFormat:@"Cannot open network input: %d",(int)result]; return;}
 self.bridgeEnabled=YES; self.sourcePicker.enabled=NO; self.outputPicker.enabled=NO; self.bridgeButton.title=@"Stop bridge";
 self.summary.stringValue=@"Listening. Waiting for Network MIDI…";
}
- (void)receive:(NSData *)data {
 if(!self.bridgeEnabled) return;
 self.received++;
 const UInt8 *bytes=data.bytes;
 NSMutableString *hex=[NSMutableString string];
 for(NSUInteger i=0;i<MIN(data.length,30);i++) [hex appendFormat:@"%02X ",bytes[i]];
 self.detail.stringValue=[@"Last received: " stringByAppendingString:hex];
 for(NSUInteger i=0;i<data.length;i++) {
  UInt8 b=bytes[i];
  if(b>=0xF8) continue;
  if(b&0x80){self.status=b<0xF0?b:0; self.dataCount=0; continue;}
  if(!self.status) continue;
  if(self.dataCount==0) {self.data0=b; self.dataCount=1; if((self.status&0xF0)==0xC0 || (self.status&0xF0)==0xD0) self.dataCount=0;}
  else {
   if(self.status==0xB5 && self.data0==0x10) {
    self.lampMessages++; OSStatus result=[self sendValue:b];
    if(result==noErr) self.forwarded++;
    else self.detail.stringValue=[NSString stringWithFormat:@"USB forwarding failed: %d",(int)result];
   }
   self.dataCount=0;
  }
 }
 self.summary.stringValue=[NSString stringWithFormat:@"Network packets received: %lu\nLamp commands received: %lu\nUSB sends accepted: %lu",(unsigned long)self.received,(unsigned long)self.lampMessages,(unsigned long)self.forwarded];
}
- (void)toggleFlash:(id)sender {
 if(self.flashTimer){[self stopFlash:nil]; return;}
 self.lampOn=YES; [self sendValue:127]; self.flashButton.title=@"Stop USB flashing";
 __weak LampReceiver *weakSelf=self;
 self.flashTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){
  LampReceiver *s=weakSelf; if(!s){[t invalidate];return;} s.lampOn=!s.lampOn;
  OSStatus status=[s sendValue:s.lampOn?127:0]; s.detail.stringValue=[NSString stringWithFormat:@"Direct USB test: %@, send status %d",s.lampOn?@"ON":@"OFF",(int)status];
 }];
}
- (void)stopFlash:(id)sender { [self.flashTimer invalidate]; self.flashTimer=nil; [self sendValue:0]; self.flashButton.title=@"Test USB flashing"; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{return YES;}
- (void)applicationWillTerminate:(NSNotification *)notification { [self stopFlash:nil]; if(self.connectedSource) MIDIPortDisconnectSource(self.inputPort,self.connectedSource); if(self.client) MIDIClientDispose(self.client); }
@end
int main(int argc,const char **argv){@autoreleasepool{ NSApplication *app=NSApplication.sharedApplication; app.activationPolicy=NSApplicationActivationPolicyRegular; LampReceiver *delegate=[LampReceiver new]; app.delegate=delegate; [app run]; } return 0;}
