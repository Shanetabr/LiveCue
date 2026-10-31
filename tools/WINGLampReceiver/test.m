#define main ReceiverApplicationMain
#import "main.m"
#undef main
int main(void) { @autoreleasepool {
 [NSApplication sharedApplication];
 LampReceiver *r=[LampReceiver new];
 r.summary=[NSTextField labelWithString:@""]; r.detail=[NSTextField labelWithString:@""];
 r.sourcePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect]; r.outputPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect];
 r.bridgeButton=[NSButton new]; r.flashButton=[NSButton new];
 MIDIClientRef client=0; MIDIPortRef out=0; MIDIEndpointRef destination=0;
 NSCAssert(MIDIClientCreate(CFSTR("Receiver integration check"),NULL,NULL,&client)==0,@"client");
 NSCAssert(MIDIOutputPortCreate(client,CFSTR("Output"),&out)==0,@"output");
 NSMutableArray<NSData *> *received=[NSMutableArray array];
 NSLock *lock=[NSLock new];
 NSCAssert(MIDIDestinationCreateWithBlock(client,CFSTR("WING Port 4 integration check"),&destination,^(const MIDIPacketList *list,void *context){
   const MIDIPacket *p=&list->packet[0];
   for(UInt32 i=0;i<list->numPackets;i++) { [lock lock]; [received addObject:[NSData dataWithBytes:p->data length:p->length]]; [lock unlock]; p=MIDIPacketNext(p); }
 })==0,@"destination");
 r.outputPort=out; r.outputs=[NSMutableArray arrayWithObject:@(destination)];
 [r.outputPicker addItemWithTitle:@"WING Port 4 integration check"];
 MIDIEndpointRef source=0; MIDIPortRef input=0;
 NSCAssert(MIDISourceCreate(client,CFSTR("Network Lamp integration check"),&source)==noErr,@"source");
 NSCAssert(MIDIInputPortCreateWithBlock(client,CFSTR("Input"),&input,^(const MIDIPacketList *list,void *context){
   const MIDIPacket *packet=&list->packet[0];
   for(UInt32 i=0;i<list->numPackets;i++) {
     NSData *data=[NSData dataWithBytes:packet->data length:packet->length];
     dispatch_async(dispatch_get_main_queue(),^{ [r receive:data]; });
     packet=MIDIPacketNext(packet);
   }
 })==noErr,@"input");
 r.inputPort=input; r.sources=[NSMutableArray arrayWithObject:@(source)];
 [r.sourcePicker addItemWithTitle:@"Network Lamp integration check"];
 [r toggleBridge:nil];
 // Test concatenated commands, running status and ignored unrelated controllers.
 UInt8 bytes[]={0xB5,0x10,0x7F,0x10,0x00,0xB0,0x11,0x7F};
 MIDIPacketList injected; MIDIPacket *first=MIDIPacketListInit(&injected);
 MIDIPacketListAdd(&injected,sizeof(injected),first,0,sizeof(bytes),bytes);
 NSCAssert(MIDIReceived(source,&injected)==noErr,@"inject input");
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
 while([deadline timeIntervalSinceNow]>0) { [lock lock]; NSUInteger total=0; for(NSData *packet in received) total+=packet.length; BOOL done=total>=6; [lock unlock]; if(done)break; [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
 UInt8 expected[]={0xB5,0x10,0x7F,0xB5,0x10,0};
 [lock lock]; NSMutableData *flattened=[NSMutableData data]; for(NSData *packet in received) [flattened appendData:packet];
 BOOL correct=[flattened isEqual:[NSData dataWithBytes:expected length:6]]; [lock unlock];
 NSCAssert(correct && r.forwarded==2 && r.lampMessages==2,@"Wrong forwarded MIDI");
 puts("PASS: receiver input subscription and parser forwarded exact lamp ON/OFF bytes to a real virtual MIDI destination, including running status; unrelated MIDI was filtered");
 [r toggleBridge:nil]; MIDIPortDispose(input); MIDIEndpointDispose(source); MIDIEndpointDispose(destination); MIDIPortDispose(out); MIDIClientDispose(client);
 return 0;
}}
