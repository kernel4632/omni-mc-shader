/*
共享中间画面与加载器常量声明：三个维度取值相同的画面格式、每帧清除、清除色、阴影与噪声常量。
调用位置：
  `rendering/buffers_main.glsl`、`rendering/buffers_nether.glsl`、`rendering/buffers_end.glsl`
  各在开头引入本文件一次；三个维度生成的入口文件在引入绘制主体之前，再引入自己那份维度声明文件。
  加载器按每个程序展开后的片元源码逐行读取 `const` 指令，所以声明必须真的被编译进程序才会生效。
可复制示例：
    `CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb) * MAIN_OUTPUT_FACTOR`   读回一号画面的线性颜色
    `texelFetch(colortex2, ivec2(0, screenSize.y - 1), 0).a`                       读自动曝光统计像素
为什么拆成共享与逐维度两层：
  加载器不评估未展开的源码，只在真正被编译的程序里看到 `const`，同一份声明写两处也会中途丢失。
  三个维度取值相同的常量只在本文件写一次；只在某个维度不同的六个常量
  （七号画面格式、八号画面格式、阴影绘制距离、一号阴影硬件比较、零号阴影多级纹理、原版遮蔽强度）
  放在各维度自己的声明文件里，值逐项照 iterationT 三份 `composite` 文件头，见 `docs/parity.md` 第十二节。
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
    九号 八位：地形写下的方块编号与生物群系，供程序化草的几何阶段查询隔壁方块；不清除、跨帧保留。
二号顶行特殊像素：横坐标零为自动曝光，二十为标题计数，四十为全局云影，六十为景深对焦深度，都在 `a` 通道。
设计原因与取舍：
    格式名只有加载器认识，GLSL 不认识，所以格式写在块注释里，这是加载器的读法；每行只写指令，说明放上一行。
    零号、三号到六号每帧清除，一、二、七号不清除以跨帧接力；三个维度按主世界取值统一写出。
    iterationT 的下界、末地文件头省略了部分清除行，依靠加载器默认值；一号画面在主世界不清除、下界末地默认清除，
    但下界与末地的合成零号每帧完整重写一号画面，清除与否不影响画面，故统一按主世界取值，见 `docs/parity.md` 第十二节。
    `sunPathRotation`、`wetnessHalflife`、`drynessHalflife` 是玩家选项，按合同由 `effects/sky/sky.glsl`、`effects/weather/weather.glsl` 定义，这里不重复。
    `shadowMapResolution`、`shadowDistance` 同样是选项，由 `effects/shadow/shadow.glsl` 定义。
*/
#ifndef OMNI_BUFFERS_INCLUDED // 只引入一次，重复声明常量会让编译失败。
#define OMNI_BUFFERS_INCLUDED // 置上标记。

/*
零号画面格式：八位就够存贴图色。
const int colortex0Format = RGBA8;
一号画面格式：十六位定点，配合四次方根编码保住暗部精度。
const int colortex1Format = RGBA16;
二号画面格式：存全局光历史与天空盒图，十六位。
const int colortex2Format = RGBA16;
三号画面格式：存法线光照图与反射数据，十六位。
const int colortex3Format = RGBA16;
四号画面格式：存半透明法线光照图，十六位。
const int colortex4Format = RGBA16;
五号画面格式：存高光材质与泛光，十六位。
const int colortex5Format = RGBA16;
六号画面格式：存半透明颜色材质与水遮罩，十六位。
const int colortex6Format = RGBA16;
九号画面格式：存方块编号与生物群系，八位；只有程序化草会写和读它。
const int colortex9Format = RGBA8;
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
const bool colortex9Clear = false; // 方块编号跨帧保留：草丛要读上一帧记下的内容，读取发生在写入之前。

// --- 阴影图设置：三个维度相同的部分 ---
const float shadowIntervalSize = 4.0; // 阴影相机按四格对齐移动，减少走动时阴影边缘闪烁。
const bool shadowtex0Nearest = false; // 零号阴影深度线性过滤。
const bool shadowtex1Mipmap = false; // 一号阴影深度不需要多级纹理。
const bool shadowtex1Nearest = false; // 一号阴影深度线性过滤。
const bool shadowcolor0Mipmap = false; // 阴影颜色不需要多级纹理。
const bool shadowcolor0Nearest = false; // 阴影颜色线性过滤。
const bool shadowcolor1Mipmap = false; // 阴影法线不需要多级纹理。
const bool shadowcolor1Nearest = false; // 阴影法线线性过滤。

// --- 其他加载器常量：三个维度相同 ---
const int noiseTextureResolution = 64; // 噪声贴图边长，与 `texture/noise.png` 一致。
const float eyeBrightnessHalflife = 10.0; // 眼部亮度平滑半衰期，单位游戏刻。
const int superSamplingLevel = 0; // 不开超采样。
#endif // 文件守卫结束。
