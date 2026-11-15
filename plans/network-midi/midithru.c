// Persistent CoreMIDI thru connection: a route kept by the system MIDI server,
// with no app running. See 1-church-day-runbook.md (Test 2b).
//   midithru add "<source>" "<destination>"   create the route (replaces an existing one)
//   midithru list                             show routes created by this tool
//   midithru remove                           delete them
#include <CoreMIDI/CoreMIDI.h>
#include <stdio.h>
#include <string.h>

static CFStringRef owner = CFSTR("com.livecue.midithru");

static void name(MIDIObjectRef object, char *out, size_t size) {
    CFStringRef value = NULL;
    strlcpy(out, "(missing)", size);
    if (object && MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &value) == noErr && value) {
        CFStringGetCString(value, out, size, kCFStringEncodingUTF8);
        CFRelease(value);
    }
}

static MIDIEndpointRef find(const char *wanted, int sources) {
    ItemCount count = sources ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations();
    for (ItemCount i = 0; i < count; i++) {
        MIDIEndpointRef endpoint = sources ? MIDIGetSource(i) : MIDIGetDestination(i);
        char found[256];
        name(endpoint, found, sizeof found);
        if (strcmp(found, wanted) == 0) return endpoint;
    }
    printf("%s \"%s\" not found. Run: midiprobe list\n", sources ? "Source" : "Destination", wanted);
    return 0;
}

static CFDataRef routes(void) {
    CFDataRef list = NULL;
    MIDIThruConnectionFind(owner, &list);
    return list;
}

static int show_or_remove(int remove) {
    CFDataRef list = routes();
    long count = list ? CFDataGetLength(list) / sizeof(MIDIThruConnectionRef) : 0;
    const MIDIThruConnectionRef *refs = list ? (const MIDIThruConnectionRef *)CFDataGetBytePtr(list) : NULL;
    if (count == 0) printf("No routes.\n");
    for (long i = 0; i < count; i++) {
        CFDataRef data = NULL;
        char from[256] = "?", to[256] = "?";
        if (MIDIThruConnectionGetParams(refs[i], &data) == noErr && data) {
            const MIDIThruConnectionParams *params = (const MIDIThruConnectionParams *)CFDataGetBytePtr(data);
            MIDIObjectRef object; MIDIObjectType type;
            if (MIDIObjectFindByUniqueID(params->sources[0].uniqueID, &object, &type) != noErr) object = 0;
            name(object, from, sizeof from);
            if (MIDIObjectFindByUniqueID(params->destinations[0].uniqueID, &object, &type) != noErr) object = 0;
            name(object, to, sizeof to);
            CFRelease(data);
        }
        if (remove) printf("Removed \"%s\" -> \"%s\" (status %d)\n", from, to, (int)MIDIThruConnectionDispose(refs[i]));
        else printf("Route \"%s\" -> \"%s\"\n", from, to);
    }
    if (list) CFRelease(list);
    return 0;
}

int main(int argc, char **argv) {
    MIDIClientRef client = 0;
    MIDIClientCreate(CFSTR("midithru"), NULL, NULL, &client);  // makes sure the MIDI server is running
    if (argc == 2 && strcmp(argv[1], "list") == 0) return show_or_remove(0);
    if (argc == 2 && strcmp(argv[1], "remove") == 0) return show_or_remove(1);
    if (argc == 4 && strcmp(argv[1], "add") == 0) {
        MIDIEndpointRef source = find(argv[2], 1), destination = find(argv[3], 0);
        if (!source || !destination) return 1;
        show_or_remove(1);
        MIDIThruConnectionParams params;
        MIDIThruConnectionParamsInitialize(&params);
        SInt32 id = 0;
        params.numSources = 1;
        params.sources[0].endpointRef = source;
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id);
        params.sources[0].uniqueID = id;
        params.numDestinations = 1;
        params.destinations[0].endpointRef = destination;
        MIDIObjectGetIntegerProperty(destination, kMIDIPropertyUniqueID, &id);
        params.destinations[0].uniqueID = id;
        CFDataRef data = CFDataCreate(NULL, (const UInt8 *)&params, MIDIThruConnectionParamsSize(&params));
        MIDIThruConnectionRef connection = 0;
        OSStatus status = MIDIThruConnectionCreate(owner, data, &connection);
        CFRelease(data);
        printf("Route \"%s\" -> \"%s\": status %d%s\n", argv[2], argv[3], (int)status,
               status == noErr ? " (created; it stays until 'midithru remove')" : " (FAILED)");
        return status == noErr ? 0 : 1;
    }
    printf("Usage:\n  midithru add \"<source>\" \"<destination>\"\n  midithru list\n  midithru remove\n");
    return 1;
}
