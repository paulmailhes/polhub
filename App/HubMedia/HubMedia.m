// hub-media (20/11): « what is playing » for the Dictée, read, paused and played again. macOS keeps MediaRemote to its
// own programs; /usr/bin/perl, one of them, loads this library and calls one of these functions — the method of
// mediaremote-adapter (BSD-3), which VoiceInk uses. Measured 20/11 on macOS 27: the state reads through Perl, and is
// refused to hub directly.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*IsPlayingFunction)(dispatch_queue_t, void (^)(Boolean));
typedef void (*PIDFunction)(dispatch_queue_t, void (^)(int));
typedef Boolean (*SendFunction)(int, CFDictionaryRef);

static void *mediaRemote(void) {
    static void *handle;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    return handle;
}

/// « 1 1234 »: playing, and the process of the app that plays; « 0 1234 »: paused.
__attribute__((visibility("default"))) void hub_media_state(void) {
    void *handle = mediaRemote();
    IsPlayingFunction isPlaying = handle ? (IsPlayingFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    PIDFunction pid = handle ? (PIDFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") : NULL;
    if (!isPlaying || !pid) return;
    dispatch_semaphore_t playingRead = dispatch_semaphore_create(0), pidRead = dispatch_semaphore_create(0);
    __block int playing = 0, owner = 0;
    isPlaying(dispatch_get_global_queue(0, 0), ^(Boolean value) { playing = value; dispatch_semaphore_signal(playingRead); });
    pid(dispatch_get_global_queue(0, 0), ^(int value) { owner = value; dispatch_semaphore_signal(pidRead); });
    dispatch_semaphore_wait(playingRead, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    dispatch_semaphore_wait(pidRead, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    printf("%d %d\n", playing ? 1 : 0, owner);
    fflush(stdout);
}

static void sendOrder(int command) {
    void *handle = mediaRemote();
    SendFunction send = handle ? (SendFunction)dlsym(handle, "MRMediaRemoteSendCommand") : NULL;
    if (!send) return;
    send(command, NULL);
    // The order leaves by XPC: the process stays a moment for it to go.
    [NSThread sleepForTimeInterval:0.2];
}

__attribute__((visibility("default"))) void hub_media_play(void) { sendOrder(0); }
__attribute__((visibility("default"))) void hub_media_pause(void) { sendOrder(1); }
