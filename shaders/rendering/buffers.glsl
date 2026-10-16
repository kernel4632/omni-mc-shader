/*
中间画面唯一约定：照 iterationT `composite.fsh` 文件头移植全部画面格式、每帧清除、清除色和阴影、噪声等加载器常量。
调用位置：只由 `rendering/composite.glsl` 引入一次。加载器扫描任意程序的源码读取这些常量，
放进同一个程序就够；别的主体不要再引入，避免同一个常量在一个程序里出现两次。
可复制示例：
    `CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb) * MAIN_OUTPUT_FACTOR`   读回一号画面的线性颜色
    `texelFetch(colortex2, ivec2(0, screenSize.y - 1), 0).a`                       读自动曝光统计像素
各画面用途（详见 `docs/parity.md` 第四节）：
    零号 八位：贴图色（伽马空间）、天体颜色、雨遮罩；每帧清成黑色、透明度一。
    一号 十六位：全局光与遮蔽 → 场景曲线编码颜色 → 色调映射后的颜色；不清除。
    二号 十六位：全局光历史、上半屏天空盒、右上角云影、顶行统计像素；不清除。
    三号 十六位：不透明法线光照图 → 反射数据 → 镜头光斑。
    四号 十六位：半透明法线光照图；延迟阶段被一百二十八立方云噪声替换。
    五号 十六位：不透明高光材质 → 泛光。
    六号 十六位：半透明颜色材质与水遮罩；延迟阶段被三十二立方云噪声替换。
    七号 十六位：焦散法线方块 → 时间抗锯齿历史；不清除。
    八号 八位、两倍尺寸：放大输出；延迟和合成阶段被预计算大气三维贴图替换。
二号顶行特殊像素：横坐标零为自动曝光，二十为标题计数，四十为全局云影，六十为景深对焦深度，都在 `a` 通道。
设计原因与取舍：
    格式名只有加载器认识，GLSL 不认识，所以格式写在块注释里，这是加载器的读法；每行只写指令，说明放上一行。
    `sunPathRotation`、`wetnessHalflife`、`drynessHalflife` 是玩家选项，按合同由 `effects/sky.glsl`、`effects/weather.glsl` 定义，这里不重复。
    `shadowMapResolution`、`shadowDistance` 同样是选项，由 `effects/shadow.glsl` 定义。
*/
#ifndef OMNI_BUFFERS_INCLUDED // 只引入一次，重复声明常量会让编译失败。
#define OMNI_BUFFERS_INCLUDED // 置上标记。

/*
零号画面格式：八位就够存贴图色。
const int colortex0Format = RGBA8;
一号画面格式：十六位定点，配合四次方根编码保住暗部精度。
const int colortex1Format = RGBA16;
二号画面格式。
const int colortex2Format = RGBA16;
三号画面格式。
const int colortex3Format = RGBA16;
四号画面格式。
const int colortex4Format = RGBA16;
五号画面格式。
const int colortex5Format = RGBA16;
六号画面格式。
const int colortex6Format = RGBA16;
七号画面格式。
const int colortex7Format = RGBA16;
八号画面格式：放大输出直接显示，八位就够。
const int colortex8Format = RGBA8;
*/

// 零号清成黑色、透明度一：天气程序把雨雪遮罩乘进 `a`，起点必须是一。
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 1.0); // 黑色、不透明。

// 每帧清除：一号、二号、七号带跨帧数据，不能清。
const bool colortex0Clear = true; // 贴图色每帧重写。
const bool colortex1Clear = false; // 场景颜色在各阶段之间接力，并作为下一帧部分输入。
const bool colortex2Clear = false; // 全局光历史、云影和统计像素要跨帧保留。
const bool colortex3Clear = true; // 法线光照图每帧重写。
const bool colortex4Clear = true; // 半透明法线光照图每帧重写。
const bool colortex5Clear = true; // 高光材质每帧重写。
const bool colortex6Clear = true; // 半透明颜色材质每帧重写。
const bool colortex7Clear = false; // 时间抗锯齿历史跨帧保留。

// --- 阴影图设置 ---
const float shadowIntervalSize = 4.0; // 阴影相机按四格对齐移动，减少走动时阴影边缘闪烁。
const float shadowDistanceRenderMul = 1.0; // 阴影绘制距离等于阴影距离。

const bool shadowHardwareFiltering1 = true; // 一号阴影深度用硬件比较采样，得到柔和边缘。
const bool shadowtex0Mipmap = true; // 零号阴影深度生成多级纹理，可变半影搜索用。
const bool shadowtex0Nearest = false; // 零号阴影深度线性过滤。
const bool shadowtex1Mipmap = false; // 一号阴影深度不需要多级纹理。
const bool shadowtex1Nearest = false; // 一号阴影深度线性过滤。
const bool shadowcolor0Mipmap = false; // 阴影颜色不需要多级纹理。
const bool shadowcolor0Nearest = false; // 阴影颜色线性过滤。
const bool shadowcolor1Mipmap = false; // 阴影法线不需要多级纹理。
const bool shadowcolor1Nearest = false; // 阴影法线线性过滤。

// --- 其他加载器常量 ---
const int noiseTextureResolution = 64; // 噪声贴图边长，与 `texture/noise.png` 一致。
const float eyeBrightnessHalflife = 10.0; // 眼部亮度平滑半衰期，单位游戏刻。
const float ambientOcclusionLevel = 1.0; // 原版环境光遮蔽强度保持满值，`GTAO` 另算。
const int superSamplingLevel = 0; // 不开超采样。
#endif // 文件守卫结束。
