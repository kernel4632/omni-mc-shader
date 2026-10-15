/*
调色与曝光：把线性场景颜色加工成屏幕看得见的颜色，并算出这一帧该用的曝光值。
它是「最终显示」和「时间合成」共用的效果能力，自身不安排绘制顺序。

调用位置：
  rendering/final.glsl     调用 omniColor，把合成好的线性颜色映射成最终屏幕颜色。
  rendering/temporal.glsl  调用 omniExposure，算自动曝光并写进历史像素供下一帧读取。
  两个文件都通过 #include "/effects/color.glsl" 引入本文件。

可复制示例：
  线性场景颜色映射成屏幕颜色：`vec3 shown = omniColor(color, exposure);`
  取当前帧曝光值：`float exposure = omniExposure(texcoord);`

本文件直接读取的画面：
  colortex5  上一帧曝光，保存在普通历史像素的绿色通道。
  colortex6  场景颜色，自动曝光在这里取九个测光点。
  colortex0  的颜色由调用方作为参数传进来，本文件不直接采样。

关键设计原因与取舍：
  高光压缩默认用 AgX 曲线，而不是简单有理映射。简单映射把所有亮部压向纯白，
  颜色一过亮就掉饱和、失去电影感；AgX 先把颜色转到宽色域再压，暗部和亮部都
  留住色彩，代价是代码更长、多两次矩阵乘。想省性能可切回简单曲线，两条路径
  都单调，都不会出现硬剪切。
  有序抖动用来打散八位色深下渐变色出现的色带。它按屏幕像素固定取阈值，不随帧
  变化，所以不会像随机噪声那样闪；代价是画面多一层极细的固定纹理。
  自动曝光先取九个测光点的对数亮度求平均，得到目标曝光再按时间缓慢逼近，避免
  亮暗突变时画面跳动。适应速度按帧时间计算，帧率高低走的是同一条曲线。
  数值有效性检查保留在这里：显卡除零、取对数都可能产生 NaN 或无穷，一旦混进
  颜色会扩散到整屏，所以在进入和离开调色流水线时各拦一次。
*/
#ifndef OMNI_COLOR
#define OMNI_COLOR
// @effect {"label":{"zh_cn":"调色","en_us":"Color"}}
// @option {"label":{"zh_cn":"曝光倍率","en_us":"Exposure"},"slider":true}
#define OMNI_EXPOSURE 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"自动曝光","en_us":"Auto exposure"}}
//#define OMNI_AUTO_EXPOSURE
// @option {"label":{"zh_cn":"对比度","en_us":"Contrast"},"slider":true}
#define OMNI_CONTRAST 1.0 // [0.75 1.0 1.1 1.25]
// @option {"label":{"zh_cn":"饱和度","en_us":"Saturation"},"slider":true}
#define OMNI_SATURATION 1.0 // [0.5 0.75 1.0 1.1 1.25]
// @option {"label":{"zh_cn":"白平衡","en_us":"White balance"},"slider":true}
#define OMNI_WHITE_BALANCE 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"亮度倍率","en_us":"Brightness"},"slider":true}
#define OMNI_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5]
// @option {"label":{"zh_cn":"色调映射","en_us":"Tone mapping"},"description":{"zh_cn":"零用简单有理曲线保持原亮度，一用 AgX 压缩高光并保留饱和。","en_us":"Zero keeps the simple rational curve; one uses AgX filmic highlight compression."}}
#define OMNI_TONE_MAP 1 // [0 1]
// @option {"label":{"zh_cn":"有序抖动","en_us":"Ordered dither"},"description":{"zh_cn":"用四乘四阈值矩阵打散八位量化色带。","en_us":"A 4x4 ordered matrix breaks 8-bit color banding."}}
#define OMNI_DITHER 1 // [0 1]
// 曝光有效性与时间历史判断都由抗锯齿能力提供，引入一次即可共用。
#include "/effects/antialiasing.glsl"

// --- 数值有效性 ---
// 判断一个数能否继续参与计算：NaN 与无穷都视为无效值。
// 单独成函数是因为后面多处都要判断，写在一处才好统一。
bool omniFinite(float value) { return !isnan(value) && !isinf(value); }
// 判断颜色能否继续参与计算：任一分量为无效值，整体即无效。
bool omniFinite(vec3 color) { return !any(isnan(color)) && !any(isinf(color)); }

// --- 高光压缩（色调映射） ---
// 简单有理映射：单调压高光，保持既有画面行为。
vec3 omniToneMapSimple(vec3 color) {
    return color/(1.0+color); // 亮部渐近于一，不出现硬剪切。
}
// AgX 色调映射：先把颜色转到宽色域工作空间，取对数压缩高动态范围，再用 S 曲线成形。
// 矩阵、曝光范围与多项式系数取自公开的最小 AgX 实现（`Troy Sobotka` 提出的 AgX），这里按公开公式独立实现，未复制任何光影源码。
// 为什么脱开线性空间：AgX 的曲线定义在归一化曝光上，直接对线性值套曲线会变形。
// 为什么要转宽色域：压缩过程中保住色相，过亮处不会一起褪成白色。
vec3 omniToneMapAgx(vec3 color) {
    const mat3 toWorking = mat3( // 线性 sRGB 到 AgX 宽色域工作空间。
        vec3(0.856627153315983, 0.137318972929847, 0.11189821299995),
        vec3(0.0951212405381588, 0.761241990602591, 0.0767994186031903),
        vec3(0.0482516061458583, 0.101439036467562, 0.811302368396859));
    const mat3 fromWorking = mat3( // 工作空间回到显示原色。
        vec3(1.1271005818144368, -0.1413297634984383, -0.14132976349843826),
        vec3(-0.11060664309660323, 1.157823702216272, -0.11060664309660294),
        vec3(-0.016493938717834573, -0.016493938717834257, 1.2519364065950405));
    const float lowestEv = -12.47393; // 承认的最暗曝光，更暗的亮度会被夹平。
    const float highestEv = 4.026069; // 承认的最亮曝光，更亮的亮度会被夹平。
    color = max(toWorking*color,vec3(1e-10)); // 取对数之前拒绝零与负值，否则得到无穷。
    color = clamp((log2(color)-lowestEv)/(highestEv-lowestEv),0.0,1.0); // 曝光归一到零至一。
    vec3 squared = color*color, fourth = squared*squared; // 先备好平方与四次方，曲线只用这几种幂。
    color = 15.5*fourth*squared-40.14*fourth*color+31.96*fourth-6.868*squared*color+0.4298*squared+0.1191*color-0.00232; // 单调 S 曲线压缩高光。
    return clamp(fromWorking*color,0.0,1.0); // 回到显示原色并限制范围。
}
// 按选项选择压缩曲线：两条路径都在线性显示空间输出等价的颜色。
vec3 omniToneMap(vec3 color) {
#if OMNI_TONE_MAP == 1
    return omniToneMapAgx(color); // AgX 电影感高光。
#else
    return omniToneMapSimple(color); // 简单有理映射。
#endif
}

// --- 八位色带的抖动 ---
// 四乘四有序阈值矩阵：像素坐标取模后得到零到一的阈值。
// 为什么是有序而不是随机：阈值钉在屏幕像素上，逐帧不变，所以画面不会闪。
float omniBayer(vec2 pixel) {
    const float thresholds[16] = float[16]( // 每个格子使用不同的量化阈值。
        0.0/16.0, 8.0/16.0, 2.0/16.0, 10.0/16.0,
        12.0/16.0, 4.0/16.0, 14.0/16.0, 6.0/16.0,
        3.0/16.0, 11.0/16.0, 1.0/16.0, 9.0/16.0,
        15.0/16.0, 7.0/16.0, 13.0/16.0, 5.0/16.0);
    int x = int(mod(pixel.x,4.0)); // 像素落在四乘四格内的列。
    int y = int(mod(pixel.y,4.0)); // 像素落在四乘四格内的行。
    return thresholds[x+y*4]; // 返回当前格的有序阈值。
}

// --- 曝光适应 ---
// 算当前帧该用的曝光：固定模式直接返回选项值；自动模式按画面亮度算目标并缓慢逼近。
// 屏幕坐标参数目前不参与计算（测光点固定在整屏），保留是为了和调用方签名统一。
float omniExposure(vec2 uv) {
#ifdef OMNI_AUTO_EXPOSURE
    float sum = 0.0; // 九个测光点的对数亮度之和。
    for (int y=0;y<3;y++) {
        for (int x=0;x<3;x++) {
            // 测光点铺满整屏且不随当前像素变化，避免局部亮暗带偏整体曝光。
            sum += log(max(omniLuminance(texture(colortex6,(vec2(x,y)+0.5)/3.0).rgb),0.001));
        }
    }
    if (!omniFinite(sum)) return OMNI_EXPOSURE; // 测光样本无效时退回固定曝光，避免无效值扩散。
    float target = clamp(0.18/exp(sum/9.0),0.25,8.0); // 目标曝光限制在合理范围，防止无限增大。
    float old = texture(colortex5,vec2(0.5)).g; // 上一帧曝光保存在普通历史像素。
    if (!omniHistoryValid() || !omniFinite(old)) return target*OMNI_EXPOSURE; // 新场景或历史无效时直接初始化。
    return mix(old,target*OMNI_EXPOSURE,1.0-exp(-clamp(frameTime,0.0,0.5)*1.5)); // 帧率无关的缓慢适应。
#else
    return OMNI_EXPOSURE; // 固定曝光无需测光采样。
#endif
}

// --- 最终调色流水线 ---
// 固定顺序加工颜色：曝光 → 白平衡 → 高光压缩 → 饱和度 → 对比度 → 显示编码 → 抖动。
// 顺序有讲究：显示编码必须最后做，抖动必须放在编码之后，否则色带会在编码时重新出现。
vec3 omniColor(vec3 color, float exposure) {
    if (!omniFinite(color) || !omniFinite(exposure)) return vec3(0.0); // 无效输入保守回退到黑色，避免异常扩散到整屏。
    color *= exposure*OMNI_BRIGHTNESS; // 亮度与曝光独立配置。
    color *= exp(vec3(0.12,0.0,-0.12)*OMNI_WHITE_BALANCE); // 中性零值不偏色。
    color = max(color,vec3(0)); // 强光映射之前拒绝负值。
    color = omniToneMap(color); // 按选项映射高动态范围，保持单调不剪切。
    color = mix(vec3(omniLuminance(color)),color,OMNI_SATURATION); // 以亮度轴调整色彩。
    color = (color-0.5)*OMNI_CONTRAST+0.5; // 围绕中间亮度调整对比。
    color = omniSrgb(clamp(color,0.0,1.0)); // 最终一步才编码到屏幕颜色。
#if OMNI_DITHER == 1
    color += (omniBayer(gl_FragCoord.xy)-0.5)/255.0; // 有序抖动打散八位量化色带。
#endif
    if (!omniFinite(color)) return vec3(0.0); // 溢出等浮点异常保守回退到黑色。
    return clamp(color,0.0,1.0); // 抖动之后仍限制在屏幕颜色范围。
}
#endif
