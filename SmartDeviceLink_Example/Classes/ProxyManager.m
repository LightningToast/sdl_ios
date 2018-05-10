//
//  ProxyManager.m
//  SmartDeviceLink-iOS

#import "AppConstants.h"
#import "AlertManager.h"
#import "AudioManager.h"
#import "Preferences.h"
#import "ProxyManager.h"
#import "SmartDeviceLink.h"
#import "VehicleDataManager.h"


typedef NS_ENUM(NSUInteger, SDLHMIFirstState) {
    SDLHMIFirstStateNone,
    SDLHMIFirstStateNonNone,
    SDLHMIFirstStateFull
};


NS_ASSUME_NONNULL_BEGIN

@interface ProxyManager () <SDLManagerDelegate>

// Describes the first time the HMI state goes non-none and full.
@property (assign, nonatomic) SDLHMILevel firstHMILevel;

@property (assign, nonatomic, getter=isTextEnabled) BOOL textEnabled;
@property (assign, nonatomic, getter=isHexagonEnabled) BOOL toggleEnabled;
@property (assign, nonatomic, getter=areImagesEnabled) BOOL imagesEnabled;

@property (strong, nonatomic) VehicleDataManager *vehicleDataManager;
@property (strong, nonatomic) AudioManager *audioManager;
@property (nonatomic, copy, nullable) RefreshUIHandler refreshUIHandler;
@end


@implementation ProxyManager

#pragma mark - Initialization

+ (instancetype)sharedManager {
    static ProxyManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[ProxyManager alloc] init];
    });
    
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _state = ProxyStateStopped;
    _firstHMILevel = SDLHMILevelNone;

    _textEnabled = YES;
    _toggleEnabled = YES;
    _imagesEnabled = YES;

    return self;
}

- (void)startIAP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];
    // Check for previous instance of sdlManager
    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration defaultConfigurationWithAppName:ExampleAppName appId:ExampleAppId]];
    [self sdlex_setupConfigurationWithLifecycleConfiguration:lifecycleConfig];
}

- (void)startTCP {
    [self sdlex_updateProxyState:ProxyStateSearchingForConnection];
    // Check for previous instance of sdlManager
    if (self.sdlManager) { return; }
    SDLLifecycleConfiguration *lifecycleConfig = [self.class sdlex_setLifecycleConfigurationPropertiesOnConfiguration:[SDLLifecycleConfiguration debugConfigurationWithAppName:ExampleAppName appId:ExampleAppId ipAddress:[Preferences sharedPreferences].ipAddress port:[Preferences sharedPreferences].port]];
    [self sdlex_setupConfigurationWithLifecycleConfiguration:lifecycleConfig];
}

- (void)sdlex_setupConfigurationWithLifecycleConfiguration:(SDLLifecycleConfiguration *)lifecycleConfiguration {
    SDLConfiguration *config = [SDLConfiguration configurationWithLifecycle:lifecycleConfiguration lockScreen:[SDLLockScreenConfiguration enabledConfigurationWithAppIcon:[UIImage imageNamed:ExampleAppLogoName] backgroundColor:nil] logging:[self.class sdlex_logConfiguration]];
    self.sdlManager = [[SDLManager alloc] initWithConfiguration:config delegate:self];

    [self startManager];
}

- (void)startManager {
    __weak typeof (self) weakSelf = self;
    [self.sdlManager startWithReadyHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            SDLLogE(@"SDL errored starting up: %@", error);
            [weakSelf sdlex_updateProxyState:ProxyStateStopped];
            return;
        }

        self.vehicleDataManager = [[VehicleDataManager alloc] initWithManager:self.sdlManager refreshUIHandler:self.refreshUIHandler];
        self.audioManager = [[AudioManager alloc] initWithManager:self.sdlManager];

        [weakSelf sdlex_updateProxyState:ProxyStateConnected];
        [weakSelf sdlex_setupPermissionsCallbacks];
        [weakSelf sdlex_showInitialData];
    }];
}

- (void)reset {
    if (self.sdlManager == nil) {
        [self sdlex_updateProxyState:ProxyStateStopped];
        return;
    }

    [self.sdlManager stop];
}


#pragma mark - Helpers

- (void)sdlex_showInitialData {
    if (![self.sdlManager.hmiLevel isEqualToEnum:SDLHMILevelFull]) {
        return;
    }

    [self sdlex_updateScreen];
    self.sdlManager.screenManager.softButtonObjects = [self sdlex_softButtons];
}

- (void)setTextEnabled:(BOOL)textEnabled {
    _textEnabled = textEnabled;
    [self sdlex_updateScreen];
}

- (void)setImagesEnabled:(BOOL)imagesEnabled {
    _imagesEnabled = imagesEnabled;
    [self sdlex_updateScreen];
    [self setToggleSoftButtonIcon:self.isHexagonEnabled imagesEnabled:imagesEnabled];
    [self setAlertSoftButtonIcon];
}

- (void)setToggleEnabled:(BOOL)hexagonEnabled {
    _toggleEnabled = hexagonEnabled;
    [self setToggleSoftButtonIcon:hexagonEnabled imagesEnabled:self.areImagesEnabled];
}

- (void)setToggleSoftButtonIcon:(BOOL)toggleEnabled imagesEnabled:(BOOL)imagesEnabled {
    SDLSoftButtonObject *object = [self.sdlManager.screenManager softButtonObjectNamed:ToggleSoftButton];
    imagesEnabled ? [object transitionToStateNamed:(toggleEnabled ? ToggleSoftButtonImageOnState : ToggleSoftButtonImageOffState)] : [object transitionToStateNamed:(toggleEnabled ? ToggleSoftButtonTextOnState : ToggleSoftButtonTextOffState)];
}

- (void)setAlertSoftButtonIcon {
    SDLSoftButtonObject *object = [self.sdlManager.screenManager softButtonObjectNamed:AlertSoftButton];
    [object transitionToNextState];
}

- (nullable RefreshUIHandler)refreshUIHandler {
    if(!_refreshUIHandler) {
        __weak typeof(self) weakSelf = self;
        weakSelf.refreshUIHandler = ^{
            [weakSelf sdlex_updateScreen];
        };
    }

    return _refreshUIHandler;
}

- (void)sdlex_updateScreen {
    SDLScreenManager *screenManager = self.sdlManager.screenManager;

    [screenManager beginUpdates];
    screenManager.textAlignment = SDLTextAlignmentLeft;
    screenManager.textField1 = self.isTextEnabled ? SmartDeviceLinkText : nil;
    screenManager.textField2 = self.isTextEnabled ? [NSString stringWithFormat:@"Obj-C %@", ExampleAppText] : nil;
    screenManager.textField3 = self.isTextEnabled ? self.vehicleDataManager.vehicleOdometerData : nil;

    if (self.sdlManager.systemCapabilityManager.displayCapabilities.graphicSupported) {
        screenManager.primaryGraphic = self.areImagesEnabled ? [SDLArtwork persistentArtworkWithImage:[UIImage imageNamed:@"sdl_logo_green"] asImageFormat:SDLArtworkImageFormatPNG] : nil;
    }

    [screenManager endUpdatesWithCompletionHandler:^(NSError * _Nullable error) {
        SDLLogD(@"Updated text and graphics, error? %@", error);
    }];
}

- (void)sdlex_setupPermissionsCallbacks {
    // This will tell you whether or not you can use the Show RPC right at this moment
    BOOL isAvailable = [self.sdlManager.permissionManager isRPCAllowed:@"Show"];
    SDLLogD(@"Show is allowed? %@", @(isAvailable));

    // This will set up a block that will tell you whether or not you can use none, all, or some of the RPCs specified, and notifies you when those permissions change
    SDLPermissionObserverIdentifier observerId = [self.sdlManager.permissionManager addObserverForRPCs:@[@"Show", @"Alert"] groupType:SDLPermissionGroupTypeAllAllowed withHandler:^(NSDictionary<SDLPermissionRPCName, NSNumber<SDLBool> *> * _Nonnull change, SDLPermissionGroupStatus status) {
        SDLLogD(@"Show changed permission to status: %@, dict: %@", @(status), change);
    }];
    // The above block will be called immediately, this will then remove the block from being called any more
    [self.sdlManager.permissionManager removeObserverForIdentifier:observerId];

    // This will give us the current status of the group of RPCs, as if we had set up an observer, except these are one-shot calls
    NSArray *rpcGroup =@[@"AddCommand", @"PerformInteraction"];
    SDLPermissionGroupStatus commandPICSStatus = [self.sdlManager.permissionManager groupStatusOfRPCs:rpcGroup];
    NSDictionary *commandPICSStatusDict = [self.sdlManager.permissionManager statusOfRPCs:rpcGroup];
    SDLLogD(@"Command / PICS status: %@, dict: %@", @(commandPICSStatus), commandPICSStatusDict);

    // This will set up a long-term observer for the RPC group and will tell us when the status of any specified RPC changes (due to the `SDLPermissionGroupTypeAny`) option.
    [self.sdlManager.permissionManager addObserverForRPCs:rpcGroup groupType:SDLPermissionGroupTypeAny withHandler:^(NSDictionary<SDLPermissionRPCName, NSNumber<SDLBool> *> * _Nonnull change, SDLPermissionGroupStatus status) {
        SDLLogD(@"Command / PICS changed permission to status: %@, dict: %@", @(status), change);
    }];
}

+ (SDLLifecycleConfiguration *)sdlex_setLifecycleConfigurationPropertiesOnConfiguration:(SDLLifecycleConfiguration *)config {
    SDLArtwork *appIconArt = [SDLArtwork persistentArtworkWithImage:[UIImage imageNamed:ExampleAppLogoName] asImageFormat:SDLArtworkImageFormatPNG];

    config.shortAppName = ExampleAppNameShort;
    config.appIcon = appIconArt;
    config.voiceRecognitionCommandNames = @[ExampleAppNameTTS];
    config.ttsName = [SDLTTSChunk textChunksFromString:ExampleAppName];
    config.language = SDLLanguageEnUs;
    config.languagesSupported = @[SDLLanguageEnUs, SDLLanguageFrCa, SDLLanguageEsMx];

    return config;
}

+ (SDLLogConfiguration *)sdlex_logConfiguration {
    SDLLogConfiguration *logConfig = [SDLLogConfiguration debugConfiguration];
    SDLLogFileModule *sdlExampleModule = [SDLLogFileModule moduleWithName:@"SDL Example" files:[NSSet setWithArray:@[@"ProxyManager"]]];
    logConfig.modules = [logConfig.modules setByAddingObject:sdlExampleModule];
    logConfig.targets = [logConfig.targets setByAddingObject:[SDLLogTargetFile logger]];
    // logConfig.filters = [logConfig.filters setByAddingObject:[SDLLogFilter filterByAllowingModules:[NSSet setWithObject:@"Transport"]]];
    logConfig.globalLogLevel = SDLLogLevelVerbose;

    return logConfig;
}

- (void)sdlex_updateProxyState:(ProxyState)newState {
    if (self.state != newState) {
        [self willChangeValueForKey:@"state"];
        _state = newState;
        [self didChangeValueForKey:@"state"];
    }
}

#pragma mark - RPC builders

#pragma mark Perform Interaction Choice Sets
static UInt32 choiceSetId = 100;

+ (NSArray<SDLChoice *> *)sdlex_createChoiceSet {
    SDLChoice *firstChoice = [[SDLChoice alloc] initWithId:1 menuName:PICSFirstChoice vrCommands:@[PICSFirstChoice]];
    SDLChoice *secondChoice = [[SDLChoice alloc] initWithId:2 menuName:PICSSecondChoice vrCommands:@[PICSSecondChoice]];
    SDLChoice *thirdChoice = [[SDLChoice alloc] initWithId:3 menuName:PICSThirdChoice vrCommands:@[PICSThirdChoice]];
    return @[firstChoice, secondChoice, thirdChoice];
}

+ (SDLPerformInteraction *)sdlex_createPerformInteraction {
    SDLPerformInteraction *performInteraction = [[SDLPerformInteraction alloc] initWithInitialPrompt:PICSInitialPrompt initialText:PICSInitialText interactionChoiceSetIDList:@[@(choiceSetId)] helpPrompt:PICSHelpPrompt timeoutPrompt:PICSTimeoutPrompt interactionMode:SDLInteractionModeBoth timeout:10000];
    performInteraction.interactionLayout = SDLLayoutModeListOnly;
    return performInteraction;
}

+ (void)sdlex_showPerformInteractionChoiceSetWithManager:(SDLManager *)manager {
    [manager sendRequest:[self sdlex_createPerformInteraction] withResponseHandler:^(__kindof SDLRPCRequest * _Nullable request, __kindof SDLRPCResponse * _Nullable response, NSError * _Nullable error) {
        if (response.resultCode != SDLResultSuccess) {
            SDLLogE(@"The Show Perform Interaction Choice Set request failed: %@", error.localizedDescription);
            return;
        }

        if ([response.resultCode isEqualToEnum:SDLResultTimedOut]) {
            // The menu timed out before the user could select an item
            [manager sendRequest:[[SDLSpeak alloc] initWithTTS:TTSGoodJob]];
        } else if ([response.resultCode isEqualToEnum:SDLResultSuccess]) {
            // The user selected an item in the menu
            [manager sendRequest:[[SDLSpeak alloc] initWithTTS:TTSYouMissed]];
        }
    }];
}

+ (SDLCreateInteractionChoiceSet *)sdlex_createOnlyChoiceInteractionSet {
    return [[SDLCreateInteractionChoiceSet alloc] initWithId:choiceSetId choiceSet:[self sdlex_createChoiceSet]];
}

# pragma mark Soft buttons

- (NSArray<SDLSoftButtonObject *> *)sdlex_softButtons {
    SDLSoftButtonState *alertImageAndTextState = [[SDLSoftButtonState alloc] initWithStateName:AlertSoftButtonImageState text:AlertSoftButtonText image:[UIImage imageNamed:CarIconImageName]];
    SDLSoftButtonState *alertTextState = [[SDLSoftButtonState alloc] initWithStateName:AlertSoftButtonTextState text:AlertSoftButtonText image:nil];

    __weak typeof(self) weakself = self;
    SDLSoftButtonObject *alertSoftButton = [[SDLSoftButtonObject alloc] initWithName:AlertSoftButton states:@[alertImageAndTextState, alertTextState] initialStateName:alertImageAndTextState.name handler:^(SDLOnButtonPress * _Nullable buttonPress, SDLOnButtonEvent * _Nullable buttonEvent) {
        if (buttonPress == nil) { return; }

        [weakself.sdlManager sendRequest:[AlertManager alertWithMessageAndCloseButton:@"You pushed the soft button!" textField2:nil]];

        SDLLogD(@"Star icon soft button press fired");
    }];

    SDLSoftButtonState *toggleImageOnState = [[SDLSoftButtonState alloc] initWithStateName:ToggleSoftButtonImageOnState text:nil image:[UIImage imageNamed:WheelIconImageName]];
    SDLSoftButtonState *toggleImageOffState = [[SDLSoftButtonState alloc] initWithStateName:ToggleSoftButtonImageOffState text:nil image:[UIImage imageNamed:LaptopIconImageName]];
    SDLSoftButtonState *toggleTextOnState = [[SDLSoftButtonState alloc] initWithStateName:ToggleSoftButtonTextOnState text:ToggleSoftButtonTextTextOnText image:nil];
    SDLSoftButtonState *toggleTextOffState = [[SDLSoftButtonState alloc] initWithStateName:ToggleSoftButtonTextOffState text:ToggleSoftButtonTextTextOffText image:nil];
    SDLSoftButtonObject *toggleButton = [[SDLSoftButtonObject alloc] initWithName:ToggleSoftButton states:@[toggleImageOnState, toggleImageOffState, toggleTextOnState, toggleTextOffState] initialStateName:toggleImageOnState.name handler:^(SDLOnButtonPress * _Nullable buttonPress, SDLOnButtonEvent * _Nullable buttonEvent) {
        if (buttonPress == nil) { return; }

        weakself.toggleEnabled = !weakself.toggleEnabled;
        SDLLogD(@"Toggle icon button press fired %d", self.toggleEnabled);
    }];

    SDLSoftButtonState *textOnState = [[SDLSoftButtonState alloc] initWithStateName:TextVisibleSoftButtonTextOnState text:TextVisibleSoftButtonTextOnText image:nil];
    SDLSoftButtonState *textOffState = [[SDLSoftButtonState alloc] initWithStateName:TextVisibleSoftButtonTextOffState text:TextVisibleSoftButtonTextOffText image:nil];
    SDLSoftButtonObject *textButton = [[SDLSoftButtonObject alloc] initWithName:TextVisibleSoftButton states:@[textOnState, textOffState] initialStateName:textOnState.name handler:^(SDLOnButtonPress * _Nullable buttonPress, SDLOnButtonEvent * _Nullable buttonEvent) {
        if (buttonPress == nil) { return; }

        weakself.textEnabled = !weakself.textEnabled;
        SDLSoftButtonObject *object = [weakself.sdlManager.screenManager softButtonObjectNamed:TextVisibleSoftButton];
        [object transitionToNextState];

        SDLLogD(@"Text visibility soft button press fired %d", weakself.textEnabled);
    }];

    SDLSoftButtonState *imagesOnState = [[SDLSoftButtonState alloc] initWithStateName:ImagesVisibleSoftButtonImageOnState text:ImagesVisibleSoftButtonImageOnText image:nil];
    SDLSoftButtonState *imagesOffState = [[SDLSoftButtonState alloc] initWithStateName:ImagesVisibleSoftButtonImageOffState text:ImagesVisibleSoftButtonImageOffText image:nil];
    SDLSoftButtonObject *imagesButton = [[SDLSoftButtonObject alloc] initWithName:ImagesVisibleSoftButton states:@[imagesOnState, imagesOffState] initialStateName:imagesOnState.name handler:^(SDLOnButtonPress * _Nullable buttonPress, SDLOnButtonEvent * _Nullable buttonEvent) {
        if (buttonPress == nil) {
            return;
        }

        weakself.imagesEnabled = !weakself.imagesEnabled;

        SDLSoftButtonObject *object = [weakself.sdlManager.screenManager softButtonObjectNamed:ImagesVisibleSoftButton];
        [object transitionToNextState];

        SDLLogD(@"Image visibility soft button press fired %d", weakself.imagesEnabled);
    }];

    return @[alertSoftButton, toggleButton, textButton, imagesButton];
}

- (void)sdlex_prepareRemoteSystem {
    SDLCreateInteractionChoiceSet *choiceSet = [self.class sdlex_createOnlyChoiceInteractionSet];
    [self.sdlManager sendRequest:choiceSet];

    __weak typeof(self) weakself = self;
    SDLMenuCell *speakCell = [[SDLMenuCell alloc] initWithTitle:ACSpeakAppNameMenuName icon:[SDLArtwork artworkWithImage:[UIImage imageNamed:SpeakBWIconImageName] asImageFormat:SDLArtworkImageFormatPNG] voiceCommands:@[ACSpeakAppNameMenuName] handler:^(SDLTriggerSource  _Nonnull triggerSource) {
        [weakself.sdlManager sendRequest:[[SDLSpeak alloc] initWithTTS:ExampleAppNameTTS]];
    }];

    SDLMenuCell *interactionSetCell = [[SDLMenuCell alloc] initWithTitle:ACShowChoiceSetMenuName icon:[SDLArtwork artworkWithImage:[UIImage imageNamed:MenuBWIconImageName] asImageFormat:SDLArtworkImageFormatPNG] voiceCommands:@[ACShowChoiceSetMenuName] handler:^(SDLTriggerSource  _Nonnull triggerSource) {
        [ProxyManager sdlex_showPerformInteractionChoiceSetWithManager:weakself.sdlManager];
    }];

    SDLMenuCell *getVehicleDataCell = [[SDLMenuCell alloc] initWithTitle:ACGetVehicleDataMenuName icon:[SDLArtwork artworkWithImage:[UIImage imageNamed:CarBWIconImageName] asImageFormat:SDLArtworkImageFormatPNG] voiceCommands:@[ACGetVehicleDataMenuName] handler:^(SDLTriggerSource  _Nonnull triggerSource) {
        [VehicleDataManager getVehicleSpeedWithManager:weakself.sdlManager];
    }];

    SDLMenuCell *recordInCarMicrophoneAudio = [[SDLMenuCell alloc] initWithTitle:ACRecordInCarMicrophoneAudioMenuName icon:[SDLArtwork artworkWithImage:[UIImage imageNamed:SpeakBWIconImageName] asImageFormat:SDLArtworkImageFormatPNG]  voiceCommands:@[ACRecordInCarMicrophoneAudioMenuName] handler:^(SDLTriggerSource  _Nonnull triggerSource) {
        [self.audioManager startRecording];
    }];

    SDLMenuCell *dialPhoneNumber = [[SDLMenuCell alloc] initWithTitle:ACDialPhoneNumberMenuName icon:nil voiceCommands:@[ACDialPhoneNumberMenuName] handler:^(SDLTriggerSource  _Nonnull triggerSource) {
        [VehicleDataManager checkPhoneCallCapabilityWithManager:self.sdlManager phoneNumber:@"555-555-5555"];
    }];

    NSMutableArray *submenuItems = [NSMutableArray array];
    for (int i = 0; i < 75; i++) {
        SDLMenuCell *cell = [[SDLMenuCell alloc] initWithTitle:[NSString stringWithFormat:@"%@ %i", ACSubmenuItemMenuName, i] icon:[SDLArtwork artworkWithImage:[UIImage imageNamed:MenuBWIconImageName] asImageFormat:SDLArtworkImageFormatPNG] voiceCommands:nil handler:^(SDLTriggerSource  _Nonnull triggerSource){}];
        [submenuItems addObject:cell];
    }
    SDLMenuCell *submenuCell = [[SDLMenuCell alloc] initWithTitle:ACSubmenuMenuName subCells:[submenuItems copy]];

    self.sdlManager.screenManager.menu = @[speakCell, getVehicleDataCell, interactionSetCell, recordInCarMicrophoneAudio, dialPhoneNumber, submenuCell];
}


#pragma mark - SDLManagerDelegate

- (void)managerDidDisconnect {
    [self sdlex_updateProxyState:ProxyStateStopped];

    // Reset our state
    self.firstHMILevel = SDLHMILevelNone;
    [self.vehicleDataManager stopManager];

    // If desired, automatically start searching for a new connection to Core
    if (ExampleAppShouldRestartSDLManagerOnDisconnect) {
        [self startManager];
    }
}

- (void)hmiLevel:(SDLHMILevel)oldLevel didChangeToLevel:(SDLHMILevel)newLevel {
    if (![newLevel isEqualToEnum:SDLHMILevelNone] && ([self.firstHMILevel isEqualToEnum:SDLHMILevelNone])) {
        // This is our first time in a non-NONE state
        self.firstHMILevel = newLevel;
        
        // Send AddCommands
        [self sdlex_prepareRemoteSystem];
        [self.vehicleDataManager subscribeToVehicleOdometer];
    }

    if ([newLevel isEqualToEnum:SDLHMILevelFull]) {
        SDLLogD(@"The HMI level is full");
    } else if ([newLevel isEqualToEnum:SDLHMILevelLimited]) {
        SDLLogD(@"The HMI level is limited");
    } else if ([newLevel isEqualToEnum:SDLHMILevelBackground]) {
        SDLLogD(@"The HMI level is background");
    } else if ([newLevel isEqualToEnum:SDLHMILevelNone]) {
        SDLLogD(@"The HMI level is none");
    }
    
    if ([newLevel isEqualToEnum:SDLHMILevelFull]) {
        // We're always going to try to show the initial state. because if we've already shown it, it won't be shown, and we need to guard against some possible weird states
        [self sdlex_showInitialData];
    }
}

- (nullable SDLLifecycleConfigurationUpdate *)managerShouldUpdateLifecycleToLanguage:(SDLLanguage)language {
    SDLLifecycleConfigurationUpdate *update = [[SDLLifecycleConfigurationUpdate alloc] init];

    if ([language isEqualToEnum:SDLLanguageEnUs]) {
        update.appName = ExampleAppName;
    } else if ([language isEqualToString:SDLLanguageEsMx]) {
        update.appName = ExampleAppNameSpanish;
    } else if ([language isEqualToString:SDLLanguageFrCa]) {
        update.appName = ExampleAppNameFrench;
    } else {
        return nil;
    }

    update.ttsName = [SDLTTSChunk textChunksFromString:update.appName];
    return update;
}

@end

NS_ASSUME_NONNULL_END
