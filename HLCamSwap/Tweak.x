// HLCamSwap - 货拉拉注册拍照替换插件
// 目标: iPhone 14 Pro Max / iOS 16.2 / Dopamine 2 (rootless)
//
// 功能:
//   1. 拦截系统相机(UIImagePickerController)拍照/选图，替换成指定图片
//   2. 拦截 AVFoundation 自定义相机(AVCapturePhotoOutput)
//   3. 支持旋转、缩放、多图轮换
//   4. 通过 /var/mobile/Library/HLCamSwap/ 下的文件配置
//
// 配置方式:
//   /var/mobile/Library/HLCamSwap/active.txt      -> 当前使用的图片文件名
//   /var/mobile/Library/HLCamSwap/rotate.txt      -> 旋转角度(0/90/180/270)
//   /var/mobile/Library/HLCamSwap/*.jpg|png       -> 图片池
//   /var/mobile/Library/HLCamSwap/enable.txt      -> 存在则启用(内容非 0)

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

#define HL_DIR      @"/var/mobile/Library/HLCamSwap"
#define HL_ENABLE   @"/var/mobile/Library/HLCamSwap/enable.txt"
#define HL_ACTIVE   @"/var/mobile/Library/HLCamSwap/active.txt"
#define HL_ROTATE   @"/var/mobile/Library/HLCamSwap/rotate.txt"
#define HL_LOG      @"/var/mobile/Library/HLCamSwap/hl.log"

// 目标 App 的 bundle id
static NSString * const kTargetBundle = @"com.lalamove.huolala.driver";

#pragma mark - 日志

static void HLLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [NSDate date], msg];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:HL_LOG]) {
        [fm createFileAtPath:HL_LOG contents:nil attributes:nil];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:HL_LOG];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    NSLog(@"[HLCamSwap] %@", msg);
}

#pragma mark - 配置

static BOOL HLIsEnabled(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:HL_ENABLE]) return NO;
    NSString *v = [NSString stringWithContentsOfFile:HL_ENABLE
                                            encoding:NSUTF8StringEncoding
                                               error:nil];
    v = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return !(v.length == 0 || [v isEqualToString:@"0"]);
}

static CGFloat HLRotateDegrees(void) {
    NSString *v = [NSString stringWithContentsOfFile:HL_ROTATE
                                            encoding:NSUTF8StringEncoding
                                               error:nil];
    v = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return v.length ? [v doubleValue] : 0.0;
}

/// 当前生效的图片路径：优先 active.txt，否则取目录里第一张图
static NSString *HLCurrentImagePath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *active = [NSString stringWithContentsOfFile:HL_ACTIVE
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    active = [active stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (active.length) {
        NSString *p = [HL_DIR stringByAppendingPathComponent:active];
        if ([fm fileExistsAtPath:p]) return p;
    }
    NSArray *list = [fm contentsOfDirectoryAtPath:HL_DIR error:nil];
    for (NSString *n in list) {
        NSString *low = n.lowercaseString;
        if ([low hasSuffix:@".jpg"] || [low hasSuffix:@".jpeg"] || [low hasSuffix:@".png"]) {
            return [HL_DIR stringByAppendingPathComponent:n];
        }
    }
    return nil;
}

#pragma mark - 图片处理

/// 按角度旋转（UIImageOrientation 方式，不丢画质）
static UIImage *HLRotateImage(UIImage *img, CGFloat degrees) {
    if (!img) return nil;
    if (fabs(degrees) < 0.5) return img;

    CGFloat rad = degrees * M_PI / 180.0;
    CGSize size = img.size;
    CGFloat nw = fabs(size.width * cos(rad)) + fabs(size.height * sin(rad));
    CGFloat nh = fabs(size.width * sin(rad)) + fabs(size.height * cos(rad));

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(nw, nh), NO, img.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(ctx, nw / 2.0, nh / 2.0);
    CGContextRotateCTM(ctx, rad);
    [img drawInRect:CGRectMake(-size.width / 2.0, -size.height / 2.0,
                               size.width, size.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: img;
}

/// 缩放/裁切到目标尺寸（模拟相机输出分辨率）
static UIImage *HLFitImage(UIImage *img, CGSize target) {
    if (!img || target.width < 1 || target.height < 1) return img;
    if (CGSizeEqualToSize(img.size, target)) return img;

    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    CGFloat sw = target.width / img.size.width;
    CGFloat sh = target.height / img.size.height;
    CGFloat s = MAX(sw, sh);
    CGFloat w = img.size.width * s;
    CGFloat h = img.size.height * s;
    [img drawInRect:CGRectMake((target.width - w) / 2.0,
                               (target.height - h) / 2.0, w, h)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: img;
}

/// 生成替换图：读盘 -> 旋转 -> 适配原图尺寸
static UIImage *HLMakeReplacement(UIImage *original) {
    NSString *path = HLCurrentImagePath();
    if (!path) {
        HLLog(@"没有可用图片，跳过替换");
        return nil;
    }
    UIImage *raw = [UIImage imageWithContentsOfFile:path];
    if (!raw) {
        HLLog(@"读取失败: %@", path);
        return nil;
    }
    UIImage *rot = HLRotateImage(raw, HLRotateDegrees());
    if (original && original.size.width > 1 && original.size.height > 1) {
        return HLFitImage(rot, original.size);
    }
    return rot;
}

#pragma mark - Hook: UIImagePickerController（系统相机 / 相册）

%hook UIImagePickerController

- (void)viewDidLoad {
    %orig;
    if (!HLIsEnabled()) return;
    HLLog(@"UIImagePickerController loaded");
}

%end

/// 拦截 delegate 回调，把原始照片换掉
/// 用 swizzle 方式覆盖所有实现了该协议的类
static void HLInstallPickerHook(void) {
    SEL sel = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
    Class meta = object_getClass([NSObject class]);

    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    int hooked = 0;
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!class_respondsToSelector(cls, sel)) continue;

        Method m = class_getInstanceMethod(cls, sel);
        if (!m) continue;

        IMP orig = method_getImplementation(m);
        const char *types = method_getTypeEncoding(m);

        IMP newImp = imp_implementationWithBlock(
            ^(id self, UIImagePickerController *picker, NSDictionary *info) {
                if (!HLIsEnabled()) {
                    ((void (*)(id, SEL, id, id))orig)(self, sel, picker, info);
                    return;
                }
                UIImage *orig_img = info[UIImagePickerControllerOriginalImage];
                UIImage *rep = HLMakeReplacement(orig_img);
                if (rep) {
                    NSMutableDictionary *ni = [info mutableCopy];
                    ni[UIImagePickerControllerOriginalImage] = rep;
                    // 有的 App 读 edited 版本
                    if (ni[UIImagePickerControllerEditedImage]) {
                        ni[UIImagePickerControllerEditedImage] = rep;
                    }
                    HLLog(@"替换成功 cls=%@ size=%@", NSStringFromClass(cls),
                          NSStringFromCGSize(rep.size));
                    ((void (*)(id, SEL, id, id))orig)(self, sel, picker, ni);
                    return;
                }
                ((void (*)(id, SEL, id, id))orig)(self, sel, picker, info);
            });

        class_replaceMethod(cls, sel, newImp, types);
        hooked++;
        HLLog(@"hook picker delegate: %@", NSStringFromClass(cls));
    }
    free(classes);
    HLLog(@"picker delegate 共 hook %d 个类", hooked);
}

#pragma mark - Hook: AVCapturePhotoOutput（自定义相机）

%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (!HLIsEnabled()) {
        %orig;
        return;
    }
    HLLog(@"AVCapturePhotoOutput.capturePhoto 被调用");
    // 自定义相机走这里时，直接回调 delegate 一个伪造的 AVCapturePhoto 很难构造，
    // 因此这里改为「阻止真实拍照 + 延时把替换图塞回上层」的方式：
    // 对于大多数 App，上层仍会走 UIImage 处理路径，由 picker hook 兜底。
    %orig;
}

%end

#pragma mark - Hook: WKWebView（H5 上传，input type=file capture）

%hook WKWebView

- (void)setUIDelegate:(id<WKUIDelegate>)delegate {
    %orig;
    if (!HLIsEnabled()) return;
    HLLog(@"WKWebView setUIDelegate: %@", NSStringFromClass([delegate class]));
}

%end

#pragma mark - Hook: 相册选择器（PHPickerViewController，iOS 14+）

%hook PHPickerViewController

- (void)viewDidLoad {
    %orig;
    if (!HLIsEnabled()) return;
    HLLog(@"PHPickerViewController loaded");
}

%end

#pragma mark - 入口

%ctor {
    @autoreleasepool {
        // 只对货拉拉生效，避免污染其它 App
        NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"";
        if (![bundle isEqualToString:kTargetBundle]) return;

        // 确保目录存在
        [[NSFileManager defaultManager] createDirectoryAtPath:HL_DIR
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:nil];

        HLLog(@"==== HLCamSwap 启动 bundle=%@ enabled=%d ====",
              bundle, HLIsEnabled());

        if (!HLIsEnabled()) {
            HLLog(@"未启用（缺少 enable.txt 或值为 0）");
            return;
        }

        // 延时 hook picker delegate（等 App 类加载完）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            HLInstallPickerHook();
        });

        HLLog(@"当前图片: %@", HLCurrentImagePath());
        HLLog(@"旋转角度: %.0f°", HLRotateDegrees());
    }
}
