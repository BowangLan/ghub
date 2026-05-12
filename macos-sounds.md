# macOS Built-in Sound Effects

Catalog of audio assets shipped with macOS, grouped by source. Compiled from a live filesystem scan of `/System/Library/Sounds`, `/System/Applications`, `/System/Library/CoreServices`, `/System/Library/Frameworks`, and `/System/Library/PrivateFrameworks`.

Preview any file with:

```bash
afplay "<full path>"
```

> Notes
> - Tier 1 sounds are the only "officially" exposed alert sounds — they appear in **System Settings → Sound → Sound Effects** and are addressable via `NSSound(named:)` using the basename (no extension).
> - Everything below Tier 1 lives inside app/framework bundles. Apple does not guarantee these paths across OS versions, but they are stable enough to use ad-hoc (e.g. for personal tooling). Avoid shipping references to them in distributed apps.
> - Speech/TTS sample corpora (`SiriTTSService`, `SpeechObjects`, `ScreenReader`) contain ~567 voice phoneme/diphone fragments and are intentionally **not enumerated** here — they are not "sound effects" in the conventional sense.

---

## Tier 1 — User-selectable alert sounds

Path: `/System/Library/Sounds/` · Format: AIFF · NSSound name = filename without extension.

| Name | Vibe |
|---|---|
| Basso | deep bass error thud |
| Blow | breathy whoosh |
| Bottle | hollow bottle pop |
| Frog | croak |
| Funk | flat error buzz |
| Glass | bright ting (system default alert) |
| Hero | triumphant chime |
| Morse | short morse-style beep |
| Ping | classic ping |
| Pop | quick pop |
| Purr | low rumble |
| Sosumi | iconic "sue-me" ding (Apple/Beatles in-joke) |
| Submarine | sonar ping |
| Tink | tiny metallic tap |

---

## Tier 2 — App-bundled sounds

Sounds embedded inside specific `/System/Applications` bundles.

| App | File |
|---|---|
| Mail | `/System/Applications/Mail.app/Contents/Resources/New Mail.aiff` |
| Mail | `/System/Applications/Mail.app/Contents/Resources/Mail Sent.aiff` |
| Mail | `/System/Applications/Mail.app/Contents/Resources/Mail Fetch Error.aiff` |
| Mail | `/System/Applications/Mail.app/Contents/Resources/Mail Scheduled.wav` |
| Books | `/System/Applications/Books.app/Contents/Frameworks/BKAudiobooks.framework/Versions/A/Resources/skipFX.aiff` |
| Audio MIDI Setup | `/System/Applications/Utilities/Audio MIDI Setup.app/Contents/Resources/MIDIReceivedSound.aiff` |
| Grapher | `/System/Applications/Utilities/Grapher.app/Contents/Resources/snapshot.aiff` |
| Screen Sharing | `/System/Applications/Utilities/Screen Sharing.app/Contents/Resources/SessionStarted.aiff` |

---

## Tier 3 — CoreServices sounds

Sounds bundled with `/System/Library/CoreServices` apps and agents.

| Source | File |
|---|---|
| Finder | `/System/Library/CoreServices/Finder.app/Contents/Resources/Invitation.aiff` |
| Game Center | `/System/Library/CoreServices/Game Center.app/Contents/Resources/GKInvite.aiff` |
| Dwell Control | `/System/Library/CoreServices/Dwell Control.app/Contents/Resources/SoundActivateItem.aiff` |
| Screen Sharing Invitation | `/System/Library/CoreServices/RemoteManagement/ScreensharingAgent.bundle/Contents/Support/SSInvitationAgent.app/Contents/Resources/Ringer.aiff` |
| Screen Sharing Accepted | `/System/Library/CoreServices/RemoteManagement/SSMenuAgent.app/Contents/Resources/Invitation Accepted.aiff` |

### Language Chooser VoiceOver instructions

`/System/Library/CoreServices/Language Chooser.app/Contents/Resources/VOInstructions-<locale>.m4a` — spoken VoiceOver instructions during initial setup. Localized for: `ar`, `ca`, `cs`, `da`, `de`, `el`, `en`, `en-AU`, `en-GB`, `en-IN`, `es`, `es-419`, `es-US`, `fi`, `fr`, `fr-CA`, `he`, `hi`, `hr`, `hu`, `id`, `it`, `ja`, `ko`, `ms`, `nb`, `nl`, `pl`, `pt-BR`, `pt-PT`, `ro`, `ru`, `sk`, `sl`, `sv`, `th`, `tr`, `uk`, `vi`, `zh-HK`, `zh-Hans`, `zh-Hant`.

---

## Tier 4 — Public framework sounds

| Framework | File | Use |
|---|---|---|
| ImageKit (Quartz) | `/System/Library/Frameworks/Quartz.framework/Versions/A/Frameworks/ImageKit.framework/Versions/A/Resources/IKBeep.aiff` | ImageKit picker beep |
| Social | `/System/Library/Frameworks/Social.framework/Versions/A/Resources/Sent.aiff` | Share-sheet "sent" confirmation |
| PHASE | `/System/Library/Frameworks/PHASE.framework/Versions/A/Resources/DrumLoop_24_48_Mono.wav` | Demo asset for spatial audio framework |

---

## Tier 5 — Private framework sounds

### ToneLibrary — Ringtones & alert tones (the iOS-inherited bank)

Base: `/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/`

#### Classic alert tones (`AlertTones/Classic/*.m4r`)

`Alert`, `Anticipate`, `Bell`, `Bloom`, `Calypso`, `Chime`, `Choo Choo`, `Descent`, `Ding`, `Electronic`, `Fanfare`, `Glass`, `Horn`, `Ladder`, `Minuet`, `News Flash`, `Noir`, `Sherwood Forest`, `Spell`, `Suspense`, `Swish`, `Swoosh`, `Telegraph`, `Tiptoes`, `Tri-Tone`, `Tweet`, `Typewriters`, `Update`

#### Modern alert tones (`AlertTones/Modern/*.m4r`)

`Aurora`, `Bamboo`, `Chord`, `Circles`, `Complete`, `Hello`, `Input`, `Keys`, `Note`, `Popcorn`, `Pulse`, `Synth`

#### EncoreInfinitum alert tones (`AlertTones/EncoreInfinitum/*.caf`)

`Antic`, `Cheers`, `Droplet`, `Handoff`, `Milestone`, `Passage`, `Portal`, `Rattle`, `Rebound`, `Slide`, `Welcome`

#### Message acknowledgement tones (`AlertTones/*.caf`)

| File | Trigger |
|---|---|
| `Text-Message-Acknowledgement-Exclamation.caf` | Tapback `!!` |
| `Text-Message-Acknowledgement-HaHa.caf` | Tapback HaHa |
| `Text-Message-Acknowledgement-Heart.caf` | Tapback heart |
| `Text-Message-Acknowledgement-QuestionMark.caf` | Tapback `?` |
| `Text-Message-Acknowledgement-ThumbsDown.caf` | Tapback thumbs-down |
| `Text-Message-Acknowledgement-ThumbsUp.caf` | Tapback thumbs-up |
| `ReceivedMessage.caf` | Generic received-message cue |
| `PhotosMemoriesNotification.caf` | Photos memory ready notification |

#### Ringtones (`Ringtones/*.m4r`)

`Alarm`, `Apex`, `Arpeggio-EncoreInfinitum`, `Ascending`, `Bark`, `Beacon`, `Bell Tower`, `Blues`, `Boing`, `Breaking-EncoreInfinitum`, `Bulletin`, `By The Seaside`, `Canopy-EncoreInfinitum`, `Chalet-EncoreInfinitum`, `Chimes`, `Chirp-EncoreInfinitum`, `Circuit`, `Constellation`, `Cosmic`, `Crickets`, `Crystals`, `Daybreak-EncoreInfinitum`, `Departure-EncoreInfinitum`, `Digital`, `Dollop-EncoreInfinitum`, `Doorbell`, `Duck`, `Harp`, `Hillside`, `Illuminate`, `Journey-EncoreInfinitum`, `Kettle-EncoreInfinitum`, `Marimba`, `Mercury-EncoreInfinitum`, `Milky Way-EncoreInfinitum`, `Motorcycle`, `Night Owl`, `Old Car Horn`, `Old Phone`, `Opening`, `Piano Riff`, `Pinball`, `Playtime`, `Presto`, `Quad-EncoreInfinitum`, `Radar`, `Radial-EncoreInfinitum`, `Radiate`, `Reflection`, `Reflection-EncoreInfinitum`, `Ripples`, `Robot`, `Scavenger-EncoreInfinitum`, `Sci-Fi`, `Seedling-EncoreInfinitum`, `Sencha`, `Shelter-EncoreInfinitum`, `Signal`, `Silk`, `Slow Rise`, `Sonar`, `Sprinkles-EncoreInfinitum`, `Stargaze`, `Steps-EncoreInfinitum`, `Storytime-EncoreInfinitum`, `Strum`, `Summit`, `Tease-EncoreInfinitum`, `Tilt-EncoreInfinitum`, `Timba`, `Time Passing`, `Trill`, `Twinkle`, `Unfold-EncoreInfinitum`, `Uplift`, `Valley-EncoreInfinitum`, `Waves`, `Xylophone`

---

### TelephonyUtilities — Calling, FaceTime, SharePlay

Base: `/System/Library/PrivateFrameworks/TelephonyUtilities.framework/`

| File | Use |
|---|---|
| `BEEP.caf` | DTMF / dial beep |
| `recurringDisclosureTwinkle.caf` | Repeating attention twinkle |
| `V2ch_hold_loop.wav` | Hold-music loop |
| `Versions/A/Resources/busy_tone_cept.caf` | Busy tone (CEPT regions) |
| `Versions/A/Resources/call_waiting_tone_cept.caf` | Call-waiting tone |
| `Versions/A/Resources/end_call_tone_cept.caf` · `.wav` | End-of-call tone |
| `Versions/A/Resources/hold.wav` | Hold cue |
| `Versions/A/Resources/let-me-join.caf` | "Knock to join" SharePlay cue |
| `Versions/A/Resources/multiway-join.caf` | Group call participant joined |
| `Versions/A/Resources/multiway-leave.caf` | Group call participant left |
| `Versions/A/Resources/mute.caf` · `unmute.caf` · `mute_fail.caf` | Mute state changes |
| `Versions/A/Resources/ringback_tone_ansi.caf` | Ringback (US/ANSI) |
| `Versions/A/Resources/ringback_tone_aus.caf` | Ringback (Australia) |
| `Versions/A/Resources/ringback_tone_cept.caf` | Ringback (CEPT/Europe) |
| `Versions/A/Resources/ringback_tone_hk.caf` | Ringback (Hong Kong) |
| `Versions/A/Resources/ringback_tone_uk.caf` | Ringback (UK) |
| `Versions/A/Resources/shareplay_activity.caf` | SharePlay activity changed |
| `Versions/A/Resources/vc~ended.caf` | FaceTime call ended |
| `Versions/A/Resources/vc~invitation-accepted.caf` | FaceTime invite accepted |

---

### AssistantServices — Siri lifecycle cues

Base: `/System/Library/PrivateFrameworks/AssistantServices.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `siri-begin-improved.caf` | Siri attention-start chime |
| `begin_sae_short.caf` | Short Siri begin variant |
| `dt-begin.caf` · `dt-cancel.caf` · `dt-confirm.caf` | Type-to-Siri state cues |
| `jbl_begin_sae.caf` · `jbl_latency_sae.caf` · `jbl_success_sae.caf` | "Just-be-listening" / Siri request feedback |
| `announce-messages-tone.wav` · `announce-messages-tone-carplay.wav` | Announce Messages tone |
| `attending-window-end.wav` | Conversation attention window ended |
| `interstitial-delay-tone.wav` | Filler tone while Siri thinks |

---

### SiriUI — Siri attention chimes (visionOS-era)

Base: `/System/Library/PrivateFrameworks/SiriUI.framework/Versions/A/Resources/`

`Siri+ Buddy V1 A 240321_ML.caf` through `Siri+ Buddy V1 F 240321_ML.caf` — six variant attention chimes (Spatial-mixed, dated 2024-03-21).

---

### MagnifierSupport — Door / People / Hand detection (Magnifier app)

Base: `/System/Library/PrivateFrameworks/MagnifierSupport.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `ax_distance_low.aiff` / `midLow` / `midHigh` / `high` | Proximity feedback ladder |
| `door_distance_low.aiff` · `door_distance_high.aiff` | Door-detection distance |
| `detection_paused.aiff` · `detection_resumed.aiff` | Detection state transitions |
| `hand_absent.aiff` | Hand left the frame |
| `point_speak_border.aiff` | Point-and-speak crossed border |
| `speech_recognition_did_begin.caf` · `speech_recognition_did_end.caf` | STT lifecycle |
| `FoundMagnifier_ML.wav` · `LostMagnifier_ML.wav` | Object found / lost |
| `LockOnMagnifier_ML.wav` · `LockOffMagnifier_ML.wav` | Object lock toggle |
| `LoopScanningMagnifier_ML.wav` | Loop scanning loop |

---

### HearingUtilities — Background sounds (Accessibility ▸ Audio)

Base: `/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources/`

Ambient loops exposed in **Settings → Accessibility → Audio → Background Sounds**:

`Airplane`, `Babble`, `Boat`, `BrownNoise`, `Bus`, `Fire`, `Night`, `Ocean`, `PinkNoise`, `QuietNight`, `Rain`, `RainOnRoof`, `Steam`, `Stream`, `Train`, `WhiteNoise` (all `.m4a`).

---

### IMDaemonCore — iMessage send/receive

Base: `/System/Library/PrivateFrameworks/IMDaemonCore.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `Sent Message.aiff` | Outbound iMessage swoosh |
| `Sent Acknowledgment.aiff` | Outbound tapback |
| `Sent Scheduled Message.caf` | Scheduled-message dispatch confirmation |

---

### HeadGestures — Head-shake/nod accessibility cues

Base: `/System/Library/PrivateFrameworks/HeadGestures.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `announce_loop.wav` | Looping prompt while detecting |
| `blip_yes.wav` · `blip_no.wav` | Detection blips |
| `confirm_yes.wav` · `confirm_no.wav` | Confirmation cues |
| `experimental_yes.wav` · `experimental_no.wav` | Experimental detection variant |

---

### AXMediaUtilities — Accessibility UI feedback

Base: `/System/Library/PrivateFrameworks/AXMediaUtilities.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `bassTone.wav` | Bass attention tone |
| `sounds/bubbleUp.aiff` · `bubbleDown.aiff` | Selection move up/down |
| `sounds/pluck1.aiff` · `pluck2.aiff` | UI pluck feedback |
| `sounds/scratch1.aiff` · `scratch2.aiff` | Scrub/scratch feedback |
| `sounds/success1.aiff` | Action succeeded |

---

### Slideshows — Photos slideshow themes (audio beds)

Base: `/System/Library/PrivateFrameworks/Slideshows.framework/Versions/A/`

| File | Theme |
|---|---|
| `PlugIns/OpusClassicProducer.opplugin/Contents/Resources/Classic.m4a` | Classic theme |
| `PlugIns/OpusMagazineProducer.opplugin/Contents/Resources/Magazine.m4a` | Magazine theme |
| `Resources/Content/Audio/Flipup.m4a` | Flipup transition |
| `Resources/Content/Audio/KenBurns.m4a` | Ken Burns |
| `Resources/Content/Audio/Origami2.m4a` | Origami |
| `Resources/Content/Audio/Reflections.m4a` | Reflections |
| `Resources/Content/Audio/SlidingPanels.m4a` | Sliding Panels |
| `Resources/Content/Audio/VintagePrints.m4a` | Vintage Prints |

---

### Navigation — Maps turn-by-turn cues

Base: `/System/Library/PrivateFrameworks/Navigation.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `Approach.caf` | Approaching maneuver |
| `TurnLeft.caf` | Turn-left cue |
| `TurnRight.caf` | Turn-right cue |

---

### ConversationKit — Recording UI

Base: `/System/Library/PrivateFrameworks/ConversationKit.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `call_recording_countdown.caf` | Call recording countdown |
| `countdown-beat.caf` | Generic countdown beat |
| `send_video_message_ML.caf` | Send video message (Spatial-mixed) |

---

### SiriMessagesCommon — Outbound message confirmation

Base: `/System/Library/PrivateFrameworks/SiriMessagesCommon.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `SentMsg.wav` | iMessage sent confirmation |
| `SentMsg3p.wav` | Third-party messaging app sent confirmation |

---

### SocialUI — Type-to-Siri state cues (duplicate set)

Base: `/System/Library/PrivateFrameworks/SocialUI.framework/Versions/A/Resources/`

`dt-begin.caf`, `dt-cancel.caf`, `dt-confirm.caf` — Mirrors the AssistantServices Type-to-Siri trio for the SocialUI surface.

---

### SpeakerRecognition — "Hey Siri" enrollment training

Base: `/System/Library/PrivateFrameworks/SpeakerRecognition.framework/Versions/A/Resources/`

`VoiceTriggerTraining_FX_0.caf` through `VoiceTriggerTraining_FX_5.caf` — six tones played during Hey-Siri voice enrollment.

---

### AudioPasscode — Continuity / Watch unlock pairing tones

Base: `/System/Library/PrivateFrameworks/AudioPasscode.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `WOCAudioPasscodeTone.wav` | "Watch on-cellular" pairing audio passcode |
| `FadingRing.wav` | Pairing ring fade |
| `FadingPingPong.wav` | Pairing ping-pong fade |
| `Lighthouse.wav` | Lighthouse pulse |

---

### SafetyMonitor — Emergency escalation

Base: `/System/Library/PrivateFrameworks/SafetyMonitor.framework/Versions/A/Resources/`

| File | Urgency |
|---|---|
| `v4_level1_urgent_ML.wav` | Level 1 (Spatial-mixed) |
| `v4_level2_urgent_ML.wav` | Level 2 |
| `v4_level3_urgent_ML.wav` | Level 3 |

---

### SiriVOX — Setup voices

Base: `/System/Library/PrivateFrameworks/SiriVOX.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `DeviceSetup-b238.wav` | Initial device setup sting |
| `SiriSummon-b238.wav` | Siri summon sting |

---

### TextToSpeechVoiceBankingSupport — Voice Banking recording

Base: `/System/Library/PrivateFrameworks/TextToSpeechVoiceBankingSupport.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `recordingWillStart.wav` | Start cue |
| `recordingDidFinish.wav` | Stop cue |

---

### PhotosUICore — People confirmation feedback

Base: `/System/Library/PrivateFrameworks/PhotosUICore.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `PXPeopleConfirmYes.caf` | "Yes, this is the right person" |
| `PXPeopleConfirmNo.caf` | "No, wrong person" |

---

### AccessibilityKit — Mouse click feedback

Base: `/System/Library/PrivateFrameworks/AccessibilitySupport.framework/Versions/A/Frameworks/AccessibilityKit.framework/Versions/A/Resources/`

| File | Use |
|---|---|
| `Click.m4a` | Synthetic click |
| `DoubleClick.m4a` | Synthetic double-click |

---

### Miscellaneous single-file frameworks

| Framework | File | Use |
|---|---|---|
| ActionKit | `soundDefault.caf` | Default Shortcuts action sound |
| CallIntelligence | `boop.caf` | Call summary / Call Intelligence cue |
| FindMyDevice | `fmd_sound.caf` | "Find My" beacon ping |
| HeadphoneSettingsUI | `E+D-US_ML.wav` | EQ/audio settings demo |
| HearingModeService_Private | `NotificationAudioTone.wav` | Hearing-mode notification tone |
| MediaPlaybackCore | `empty.m4a` | Silent placeholder track |
| PersonalAudio | `Enrollment_2.caf` | Personalized Spatial Audio enrollment cue |
| Sharing | `airdrop_invite.caf` | AirDrop invitation chime |
| SiriTTS | `AdditionalResources/AssistantEtiquette.wav` | Siri assistant etiquette demo |
| WorkflowEditor | `Reorder.aiff` | Shortcuts editor reorder cue |
| WorkoutAnnouncements | `workout_announce.caf` | Workout-progress announcement bed |

---

## Tier 6 — Excluded by design

These bundles contain audio assets, but they are TTS / speech-recognition data, not effects:

- `/System/Library/PrivateFrameworks/ScreenReader.framework` (223 files) — VoiceOver phoneme samples.
- `/System/Library/PrivateFrameworks/SiriTTSService.framework` (188 files) — Siri TTS unit samples.
- `/System/Library/PrivateFrameworks/SpeechObjects.framework` (156 files) — Speech-recognition reference clips.

---

## Quick usage

Swift (Tier 1 only — guaranteed API):

```swift
NSSound(named: "Glass")?.play()
```

`afplay` from a shell script — any tier:

```bash
afplay /System/Library/Sounds/Glass.aiff
afplay "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Marimba.m4r"
```

AppKit — preview file directly:

```swift
NSSound(contentsOfFile: "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/Modern/Aurora.m4r", byReference: true)?.play()
```
