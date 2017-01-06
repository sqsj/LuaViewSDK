//
//
//  lv5.1.4
//
//  Created by dongxicheng on 11/27/14.
//  Copyright (c) 2014 dongxicheng. All rights reserved.
//

#import "LView.h"
#import "LVHeads.h"
#import "LVExGlobalFunc.h"
#import "LVTimer.h"
#import "LVDebuger.h"
#import "LVNativeObjBox.h"
#import "LVBlock.h"
#import "LVPkgManager.h"
#import "UIView+LuaView.h"
#import "LVDebugConnection.h"
#import "LVDebugConnection.h"
#import "LVCustomPanel.h"
#import <objc/runtime.h>
#import "LVRSA.h"
#import "LVBundle.h"
#import "LVButton.h"
#import "LVScrollView.h"
#import "LView.h"
#import "LVTimer.h"
#import "LVUtil.h"
#import "LVPagerIndicator.h"
#import "LVLoadingIndicator.h"
#import "LVImage.h"
#import "LVWebView.h"
#import "LVLabel.h"
#import "LVBaseView.h"
#import "LVTransform3D.h"
#import "LVTextField.h"
#import "LVAnimate.h"
#import "LVAnimator.h"
#import "LVDate.h"
#import "LVAlert.h"
#import "LVSystem.h"
#import "LVDB.h"
#import "LVGesture.h"
#import "LVTapGesture.h"
#import "LVPanGesture.h"
#import "LVPinchGesture.h"
#import "LVRotationGesture.h"
#import "LVHttp.h"
#import "LVData.h"
#import "LVSwipeGesture.h"
#import "LVLongPressGesture.h"
#import "LVDebuger.h"
#import "LVDownloader.h"
#import "LVAudioPlayer.h"
#import "LVFile.h"
#import "LVStyledString.h"
#import "LVNativeObjBox.h"
#import "LVCollectionView.h"
#import "LVEmptyRefreshCollectionView.h"
#import "LVStruct.h"
#import "LVNavigation.h"
#import "LVCustomPanel.h"
#import "LVCustomView.h"
#import "LVPagerView.h"
#import "LVCanvas.h"
#import "LVEvent.h"

@interface LView ()
@property (nonatomic,strong) id mySelf;
@property (nonatomic,assign) BOOL stateInited;
@property (nonatomic,assign) BOOL loadedDebugScript;
@property (atomic,assign) NSInteger callLuaTimes;

@property (nonatomic,strong) LVRSA* rsa;

@property (nonatomic,assign) BOOL isOnShowed;
@end

@implementation LView

-(id) init{
    self = [super init];
    if( self ){
        [self myInit];
        [self registeLibs];
    }
    return self;
}

-(id) initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if( self ){
        [self myInit];
        [self registeLibs];
    }
    return self;
}

#pragma mark - init

-(void) myInit{
    self.disableAnimate = YES;
    self.closeLayerMode = YES;
    self.mySelf = self;
    self.backgroundColor = [UIColor clearColor];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onForeground)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    self.lv_lview = self;
    self.rsa = [[LVRSA alloc] init];
    self.bundle = [[LVBundle alloc] init];
}

-(void) dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.debugConnection closeAll];
}

#pragma mark - run
-(NSString*) runFile:(NSString*) fileName{
    self.runInSignModel = FALSE;
    NSData* code = [self.bundle scriptWithName:fileName];

    return [self runData:code fileName:fileName];
}

-(NSString*) runSignFile:(NSString*) fileName{
    self.runInSignModel = TRUE;
    NSData* code = [self.bundle signedScriptWithName:fileName rsa:self.rsa];

    return [self runData:code fileName:fileName];
}

-(NSString*) runPackage:(NSString*) packageName {
    return [self runPackage:packageName args:nil];
}

-(NSString*) runPackage:(NSString*) packageName args:(NSArray*) args{
    self.runInSignModel = TRUE;
    
    NSString *packagePath = [LVPkgManager rootDirectoryOfPackage:packageName];
    [self.bundle addScriptPath:packagePath];
    [self.bundle addResourcePath:packagePath];
    
    NSString* fileName = @"main.lv";
    NSString* ret = [self runSignFile:fileName];
    lua_State* L = self.l;
    if( ret==nil && L ) {
        for( int i=0; i<args.count; i++ ){
            id obj = args[i];
            lv_pushNativeObject( L, obj );
        }
        lua_getglobal(L, "main");// function
        if( lua_type(L, -1) == LUA_TFUNCTION ) {
            ret = lv_runFunctionWithArgs(L, (int)args.count, 0);
        }
    }
    return ret;
}

-(void) checkDebugOrNot:(const char*) chars length:(NSInteger) len fileName:(NSString*) fileName {
    if( self.debugConnection.printToServer ){
        NSMutableData* data = [[NSMutableData alloc] init];
        [data appendBytes:chars length:len];
        
        [self.debugConnection sendCmd:@"loadfile" fileName:fileName info:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    }
}

- (NSString*)loadFile:(NSString *)fileName {
    NSData* code = [self.bundle scriptWithName:fileName];
    return [self loadData:code fileName:fileName];
}

- (NSString*)loadSignFile:(NSString *)fileName {
    NSData* code = [self.bundle signedScriptWithName:fileName rsa:self.rsa];
    return [self loadData:code fileName:fileName];
}

- (NSString*)loadData:(NSData *)data fileName:(NSString *)fileName {
    return [self loadData:data fileName:fileName changeGrammar:YES];
}

- (NSString*)loadData:(NSData *)data fileName:(NSString *)fileName changeGrammar:(BOOL)changeGrammar{
    if( changeGrammar ) {
        data = lv_toStandLuaGrammar(data);
    }
    if (!data || !data.length || !fileName || !fileName.length) {
        LVError( @"running chars == NULL, file:%@", fileName);
        return [NSString stringWithFormat:@"running chars == NULL, file:%@",fileName];
    }
    
#ifdef DEBUG
    [self checkDeuggerIsRunningToLoadDebugModel];
    [self checkDebugOrNot:data.bytes length:data.length fileName:fileName];
#endif
    
    lua_State* L = self.l;
    int error = luaL_loadbuffer(L, data.bytes, data.length, fileName.UTF8String);
    if (error) {
        const char* s = lua_tostring(L, -1);
        LVError( @"%s", s );
#ifdef DEBUG
        NSString* string = [NSString stringWithFormat:@"[LuaView][error] %s\n",s];
        lv_printToServer(L, string.UTF8String, 0);
#endif
        return [NSString stringWithFormat:@"%s",s];
    } else {
        return nil;
    }
}

#ifdef DEBUG
extern char g_debug_lua[];

-(NSString*) loadDebugModel{
    NSData* data = [[NSData alloc] initWithBytes:g_debug_lua length:strlen(g_debug_lua)];
    return [self runData:data fileName:@"debug.lua" changeGrammar:NO];
}

- (void) callLuaToExecuteServerCmd{
    [self performSelectorOnMainThread:@selector(callLuaToExecuteServerCmd0) withObject:nil waitUntilDone:NO];
}

- (void) callLuaToExecuteServerCmd0{
    NSString* cmd = self.debugConnection.receivedArray.lastObject;
    if( cmd ) {
        [self.debugConnection.receivedArray removeLastObject];
    }
    if( [cmd isKindOfClass:[NSString class]] ) {
        [self callLua:@"debug_runing_execute" args:@[cmd]];
    }
}


-(void) checkDeuggerIsRunningToLoadDebugModel{
    if( self.debugConnection== nil) {
        self.debugConnection = [[LVDebugConnection alloc] init];
        self.debugConnection.lview = self;
    }

    if( [self.debugConnection waitUntilConnectionEnd]>0 ) {
        if( self.loadedDebugScript == NO ) {
            self.loadedDebugScript = YES;
            [self.debugConnection sendCmd:@"log" info:@"[LuaView][调试日志] 开始调试!\n"];
            [self loadDebugModel];// 加载调试模块
        }
    }
}
#else
- (void) callLuaToExecuteServerCmd{
}
#endif

static void *l_alloc (void *ud, void *ptr, size_t osize, size_t nsize) {
    (void)ud;
    (void)osize;
    if (nsize == 0) {
        free(ptr);
        return NULL;
    }
    else
        return realloc(ptr, nsize);
}


-(void) registeLibs{
    if( !self.stateInited ) {
        self.stateInited = YES;
        self.l =  lua_newstate(l_alloc, (__bridge void *)(self));
        luaL_openlibs(self.l);
        NSArray* arr = nil;
        arr = @[
                [LVSystem class],
                [LVData class],
                [LVStruct class],
                [LVBaseView class],
                [LVButton class],
                [LVImage class],
                [LVWebView class],
                [LVLabel class],
                [LVScrollView class],
                [LVCollectionView class],
                [LVEmptyRefreshCollectionView class],
                [LVPagerView class],
                [LVCustomView class],
                [LVCanvas class],
                [LVEvent class],
                [LVTimer class],
                [LVPagerIndicator class],
                [LVCustomPanel class],
                [LVTransform3D class],
                [LVAnimator class],
                [LVTextField class],
                [LVAnimate class],
                [LVDate class],
                [LVAlert class],
                [LVDB class],
                [LVGesture class],
                [LVTapGesture class],
                [LVPinchGesture class],
                [LVRotationGesture class],
                [LVSwipeGesture class],
                [LVLongPressGesture class],
                [LVPanGesture class],
                [LVLoadingIndicator class],
                [LVHttp class],
                [LVDownloader class],
                [LVFile class],
                [LVAudioPlayer class],
                [LVStyledString class],
                [LVNavigation class],
                [LVExGlobalFunc class],
                [LVNativeObjBox class],
                [LVDebuger class],
                ];
        self.registerClasses = arr;
        [self registerAllClass];
    }
}

-(void) registerAllClass{
    lua_State* L = self.l;
    //清理栈
    for( NSInteger i =0; i<self.registerClasses.count; i++ ){
        lua_settop(L, 0);
        lua_checkstack(L, 256);
        id c = self.registerClasses[i];
        [c lvClassDefine:L globalName:nil];
    }
    //清理栈
    lua_settop(L, 0);
}

-(NSString*) runData:(NSData *)data fileName:(NSString*)fileName{
    return [self runData:data fileName:fileName changeGrammar:YES];
}

-(NSString*) runData:(NSData*) data fileName:(NSString*) fileName changeGrammar:(BOOL) changeGrammar{
    if( changeGrammar ) {
        data = lv_toStandLuaGrammar(data);
    }
    lua_State* L = self.l;
    if( L==NULL ){
        LVError( @"Lua State is released !!!");
        return @"Lua State is released !!!";
    }
    if( fileName==nil ){
        static int i = 0;
        fileName = [NSString stringWithFormat:@"%d.lua",i];
    }
    if( data.length<=0 ){
        LVError(@"running chars == NULL, file: %@",fileName);
        return [NSString stringWithFormat:@"running chars == NULL, file: %@",fileName];
    }
#ifdef DEBUG
    [self checkDeuggerIsRunningToLoadDebugModel];
    [self checkDebugOrNot:data.bytes length:data.length fileName:fileName];
#endif
    
    int error = -1;
    error = luaL_loadbuffer(L, data.bytes , data.length, fileName.UTF8String) ;
    if ( error ) {
        const char* s = lua_tostring(L, -1);
        LVError( @"%s", s );
#ifdef DEBUG
        NSString* string = [NSString stringWithFormat:@"[LuaView][error] %s\n",s];
        lv_printToServer(L, string.UTF8String, 0);
#endif
        return [NSString stringWithFormat:@"%s",s];
    } else {
        return lv_runFunction(L);
    }
}

-(int) globalNumber:(const char*) globalName{
    lua_State* L = self.l;
    if ( L ==nil ){
        LVError( @"Lua State is released !!!");
        return 0;
    }
    lua_getglobal(L, globalName);
    
    if( !lua_isnumber(L, -1) ){
        //是否需要出栈？？？
        LVError(@"  '%s'  should be a number",globalName );
        return 0;
    } else {
        return (int) lua_tonumber(L, -1);
    }
}

-(NSString*) globalString:(const char*) globalName{
    lua_State* L = self.l;
    if ( L ==nil ){
        LVError( @"Lua State is released !!!");
        return nil;
    }
    lua_getglobal(L, globalName);
    
    if( !lua_isstring(L, -1) ){
        //是否需要出栈？？？
        LVError(@" '%s'  should be a number",globalName );
        return nil;
    } else {
        const char* chars = lua_tolstring(L, -1, NULL);
        if( chars ){
            return [NSString stringWithFormat:@"%s",chars];
        }
        return nil;
    }
}


#pragma mark - setFrame

-(void) releaseLuaView {
    [self performSelectorOnMainThread:@selector(freeMySelf) withObject:nil waitUntilDone:NO];
}

-(void) freeMySelf {
    [self removeFromSuperview];
    lua_State* l = self.l;
    self.l = NULL;
    if( l ){
        lua_close(l);
        l = NULL;
    }
    self.mySelf = nil;
}

//----------------------------------------------------------------------------------------


#pragma mark - view appear

-(void) viewWillAppear{
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"ViewWillAppear"];
    }
}

-(void) viewDidAppear{
    self.isOnShowed = YES;
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"onShow"];//@"ViewDidAppear"
    }
}

-(void) viewWillDisAppear{
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"ViewWillDisAppear"];
    }
}

-(void) viewDidDisAppear{
    self.isOnShowed = NO;
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"onHide"];//@"ViewDidDisAppear"
    }
}

-(void) onForeground {
    lua_State* L = self.l;
    if( L && self.isOnShowed ) {
        lua_checkstack32(L);
        lua_pushboolean(L, YES);
        [self lv_callLuaByKey1:@"onShow" key2:nil argN:1];
    }
}

-(void) onBackground {
    lua_State* L = self.l;
    if( L && self.isOnShowed ) {
        lua_checkstack32(L);
        lua_pushboolean(L, YES);
        [self lv_callLuaByKey1:@"onHide" key2:nil argN:1];
    }
}

- (void)didMoveToSuperview{
    [super didMoveToSuperview];
    
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"DidMoveToSuperview"];
    }
}

- (void)didMoveToWindow{
    [super didMoveToWindow];
    
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"DidMoveToSuperview"];
    }
}

#pragma mark - keyboard

-(void) keyboardWillShow:(NSNotification *)notification {
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"KeyboardWillShow"];
    }
}
-(void) keyboardDidShow:(NSNotification *)notification {
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"KeyboardDidShow"];
    }
}
-(void) keyboardWillHide:(NSNotification *)notification {
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"KeyboardWillHide"];
    }
}
-(void) keyboardDidHide:(NSNotification *)notification {
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@"KeyboardDidHide"];
    }
}

#pragma mark - 摇一摇相关方法
// 摇一摇开始摇动
- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    lua_State* L = self.l;
    if (event.subtype == UIEventSubtypeMotionShake) {
        if( L ) {
            lua_checkstack32(L);
            [self lv_callLuaByKey1:@"ShakeBegin"];
        }
    }
}

// 摇一摇取消摇动
- (void)motionCancelled:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (event.subtype == UIEventSubtypeMotionShake) {
        lua_State* L = self.l;
        if( L ) {
            lua_checkstack32(L);
            [self lv_callLuaByKey1:@"ShakeCanceled"];
        }
    }
}

// 摇一摇摇动结束
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (event.subtype == UIEventSubtypeMotionShake) {
        lua_State* L = self.l;
        if( L ) {
            lua_checkstack32(L);
            [self lv_callLuaByKey1:@"ShakeEnded"];
        }
    }
}

#pragma mark - layout

-(void) layoutSubviews{
    [super layoutSubviews];
    
    lua_State* L = self.l;
    if( L ) {
        lua_checkstack32(L);
        [self lv_callLuaByKey1:@STR_ON_LAYOUT];
    }
}

-(void) addSubview:(UIView *)view{
    if( self.contentViewIsWindow && self.conentView ){
        [self.conentView addSubview:view];
    } else {
        [super addSubview:view];
    }
}

-(void) setFrame:(CGRect)frame{
    if( self.contentViewIsWindow && self.conentView ){
        [self.conentView setFrame:frame];
    } else {
        [super setFrame:frame];
        [self.callback luaviewFrameDidChange:self];
    }
}

-(CGRect) frame{
    if( self.contentViewIsWindow && self.conentView ){
        return self.conentView.frame;
    } else {
        return super.frame;
    }
}

-(void) setBackgroundColor:(UIColor *)backgroundColor{
    if( self.contentViewIsWindow && self.conentView ){
        [self.conentView setBackgroundColor:backgroundColor];
    } else {
        [super setBackgroundColor:backgroundColor];
    }
}

-(UIColor*) backgroundColor{
    if( self.contentViewIsWindow && self.conentView ){
        return [self.conentView backgroundColor];
    } else {
        return [super backgroundColor];
    }
}

-(void) setClipsToBounds:(BOOL)clipsToBounds{
    if( self.contentViewIsWindow && self.conentView ){
        [self.conentView setClipsToBounds:clipsToBounds];
    } else {
        [super setClipsToBounds:clipsToBounds];
    }
}

-(BOOL) clipsToBounds{
    if( self.contentViewIsWindow && self.conentView ){
        return self.conentView.clipsToBounds;
    } else {
        return [super clipsToBounds];
    }
}

-(void) setAlpha:(CGFloat)alpha{
    if( self.contentViewIsWindow && self.conentView ){
        [self.conentView setAlpha:alpha];
    } else {
        [super setAlpha:alpha];
    }
}

-(CGFloat) alpha{
    if( self.contentViewIsWindow && self.conentView ){
        return self.conentView.alpha;
    } else {
        return [super alpha];
    }
}

-(void) setCenter:(CGPoint)center{
    if( self.contentViewIsWindow && self.conentView ){
        [self.conentView setCenter:center];
    } else {
        [super setCenter:center];
    }
}

-(CGPoint) center{
    if( self.contentViewIsWindow && self.conentView ){
        return [self.conentView center];
    } else {
        return [super center];
    }
}

-(void) setHidden:(BOOL)hidden{
    if( self.contentViewIsWindow && self.conentView ){
        [self.conentView setHidden:hidden];
    } else {
        [super setHidden:hidden];
    }
}

-(BOOL) isHidden{
    if( self.contentViewIsWindow && self.conentView ){
        return [self.conentView isHidden];
    } else {
        return [super isHidden];
    }
}

-(CALayer*) layer{
    if( self.contentViewIsWindow && self.conentView ){
        return [self.conentView layer];
    } else {
        return [super layer];
    }
}

#pragma mark - call lua global function
-(NSString*) callLua:(NSString*) functionName tag:(id) tag environment:(UIView*)environment args:(NSArray*) args{
    lua_State* L = self.l;
    if( L ){
        lua_checkstack(L, 8 + (int)args.count*2);
        self.conentView = environment;
        self.contentViewIsWindow = YES;
        
        [LVUtil pushRegistryValue:L key:tag]; // param1: cell
        
        if( lua_type(L, -1)==LUA_TNIL ) {// if param1==nil , create param1
            lua_newtable(L);
            
            [LVUtil registryValue:L key:tag stack:-1];
        }
        for( int i=0; i<args.count; i++ ){
            id obj = args[i];
            lv_pushNativeObject(L,obj);
        }
        lua_getglobal(L, functionName.UTF8String);// function
        NSString* ret = lv_runFunctionWithArgs(L, (int)args.count+1, 0);
        self.conentView = nil;
        self.contentViewIsWindow = NO;
        return ret;
    }
    return nil;
}

-(NSString*) callLua:(NSString*) functionName environment:(UIView*) environment args:(NSArray*) args{
    return [self callLua:functionName tag:environment environment:environment args:args];
}

-(NSString*) callLua:(NSString*) functionName args:(NSArray*) args{
    lua_State* L = self.l;
    if( L ){
        lua_checkstack(L, (int)args.count*2 + 2);
        self.conentView = nil;
        self.contentViewIsWindow = NO;
        
        for( int i=0; i<args.count; i++ ){
            id obj = args[i];
            lv_pushNativeObject(L,obj);
        }
        lua_getglobal(L, functionName.UTF8String);// function
        return lv_runFunctionWithArgs(L, (int)args.count, 0);
    }
    return nil;
}

-(LVBlock*) getLuaBlock:(NSString*) name{
    lua_State* L = self.l;
    if ( L ==nil ){
        LVError( @"Lua State is released !!!");
        return nil;
    }
    return [[LVBlock alloc] initWith:L globalName:name];
}

#pragma mark - registe object.method

-(void) registerObject:(id) object forName:(NSString*) name sel:(SEL) sel {
    [LVNativeObjBox registeObjectWithL:self.l nativeObject:object name:name sel:sel weakMode:YES];
}

-(void) registerObject:(id) object forName:(NSString*) name sel:(SEL) sel weakMode:(BOOL)weakMode{
    [LVNativeObjBox registeObjectWithL:self.l nativeObject:object name:name sel:sel weakMode:weakMode];
}

-(void) registerObject:(id) object forName:(NSString*) name{
    [LVNativeObjBox registeObjectWithL:self.l nativeObject:object name:name sel:nil weakMode:YES];
}

-(void) registerObject:(id) object forName:(NSString*) name weakMode:(BOOL)weakMode{
    [LVNativeObjBox registeObjectWithL:self.l nativeObject:object name:name sel:nil weakMode:weakMode];
}


- (void)setObject:(id)object forKeyedSubscript:(NSObject <NSCopying> *)key{
    lua_State* L = self.l;
    if ( L ==nil ){
        LVError( @"Lua State is released !!!");
        return;
    }
    if( [key isKindOfClass:[NSString class]] && class_isMetaClass(object_getClass(object)) ) {
        if( [object respondsToSelector:@selector(lvClassDefine:globalName:)] ) {
            [object lvClassDefine:L globalName:(NSString*)key];
            return;
        }
    }
    if ( [key isKindOfClass:[NSString class]] ){
        [LVNativeObjBox registeObjectWithL:L nativeObject:object name:(NSString*)key sel:nil weakMode:YES];
    }
}

-(void) unregisteObjectForName:(NSString*) name{
    lua_State* L = self.l;
    if ( L ==nil ){
        LVError( @"Lua State is released !!!");
        return ;
    }
    [LVNativeObjBox unregisteObjectWithL:L name:name];
}

#pragma mark - package

+(void) downLoadPackage:(NSString*)packageName withInfo:(NSDictionary*)info{
    [LVPkgManager downLoadPackage:packageName withInfo:info];
}

-(BOOL) argumentToBool:(int) index{
    lua_State* L = self.l;
    if ( L ) {
        return lua_toboolean(L, index);
    }
    return NO;
}

-(double)  argumentToNumber:(int) index{
    lua_State* L = self.l;
    if ( L ) {
        return lua_tonumber(L, index);
    }
    return 0;
}

-(id) argumentToObject:(int) index{
    lua_State* L = self.l;
    if ( L ) {
        return lv_luaValueToNativeObject(L, index);
    }
    return 0;
}

-(NSString*) description{
    return [NSString stringWithFormat:@"<View(0x%x) frame = %@>", (int)[self hash], NSStringFromCGRect(self.frame) ];
}

-(void) containerAddSubview:(UIView *)view{
    if( self.conentView ) {
        lv_addSubview(self, self.conentView, view);
    } else {
        lv_addSubview(self, self, view);
    }
}

// 证书

- (void) setPublicKeyFilePath:(NSString*) filePath{
    [self.rsa setPublicKeyFilePath:filePath];
}

@end
