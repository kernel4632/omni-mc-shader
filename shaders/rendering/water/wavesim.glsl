/*
波浪模拟的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/water/wavesim.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_WATER_WAVESIM_INCLUDED
#define OMNI_RENDER_WATER_WAVESIM_INCLUDED
#include "/effects/water/wavesim.glsl"
/*
波浪模拟：玩家在水面上移动时，往一张随玩家平移的水面模拟场里注入扰动，让波纹自己传播、衰减。
来源：Eclipse `dimensions/prepare.csh`、`prepare1.csh`、`prepare2.csh` 与 `shaders.properties` 里的
  `WATER_INTERACTION == 2`「波浪模拟」（Eclipse 菜单里的同名选项）；算法逐行搬运。
  与原实现的差别：跨帧状态（上一帧相机、模拟网格原点、位移累加器、上次模拟时刻、扰动半径）原本存在
  Eclipse 的共享缓冲里，本项目没有共享缓冲，改用一张四乘一的小图像承载，读写方式与本项目光传播体积一致。
调用位置：
  `rendering/watersim.glsl` 的三个计算阶段读写下方的图像，算出波高与坡度；
  `rendering/translucent.glsl` 的水面片元调用 `omniWaveSimNormal` 把模拟波法线混进基础波法线。
可复制示例：
  `vec4 w = omniWaveSimNormal(omniWaveSim2Tex, omniWaveStateTex, worldPos, upness);`  取模拟法线与权重
  `vec2 origin = texelFetch(omniWaveStateTex, ivec2(1, 0), 0).xy;`                    读模拟网格原点的水平位置
设计原因与取舍：
  一、只在开启波浪模拟且加载器提供自定义图像能力时参与编译，默认关闭，关闭时整段不产生任何代码，画面不变；
  二、模拟场固定边长为 1024、网格缩放 0.02、时间步长 0.6、平移系数 -20、模拟帧率每秒 60 帧，
     取 Eclipse 的低配档，与 `rendering/pipeline.properties` 里登记的图像尺寸必须一致，换档要两处同时改；
  三、水面片元只按模拟坡度造型，不改顶点位置；这与 Eclipse 默认一致（顶点位移只在它另开的
     `LARGE_WAVE_DISPLACEMENT` 选项里出现），所以水面轮廓不变，只有波纹光泽变化；
  四、是否「站在水面上」用眼睛是否浸在水里近似：本项目没有 Eclipse 的体素方块与载具数据，做不出精确判断。
*/


// 只有开启选项且加载器真的提供自定义图像能力，才打开整段实现；两者缺一，下面什么都不编译。
#if OMNI_WAVE_SIMULATION && defined IRIS_FEATURE_CUSTOM_IMAGES
	#define OMNI_WAVE_SIM_ON 1 // 单一开关，图像声明、计算与采样都看它，避免半开半关对不上。
#endif

// --- 固定档位参数：首版不暴露成菜单，取 Eclipse 的低配档；改这里要同时改 pipeline.properties 的图像尺寸 ---
// 这些常量放在开关之外一直声明：计算阶段的工作组数要用它们，而工作组数在任何开关取值下都必须有效。
const int OMNI_WAVE_SIM_RES = 1024; // 模拟场边长，单位纹素；与登记的图像长宽必须相同，否则下标会错位。
const float OMNI_WAVE_SIM_NORMAL_SCALE = 0.02; // 世界一格对应多少归一化坐标（Eclipse 距离档取 0.02）。
const float OMNI_WAVE_SIM_DELTA = 0.6; // 每次模拟推进的时间步长；越大传播越快、越容易发散（低配档取 0.6）。
const float OMNI_WAVE_SIM_MOVE_SCALE = -20.0; // 玩家每移动一格，模拟场沿反方向平移的纹素，用来抵消观察者移动。
const float OMNI_WAVE_SIM_FRAMETIME = 1.0 / 60.0; // 模拟推进的固定间隔，即每秒六十次，与游戏帧率无关。

#ifdef OMNI_WAVE_SIM_ON // 关闭时整段实现不进编译单元，默认画面逐位不变。

#ifdef OMNI_COMPUTE // 计算阶段读写图像；片元阶段只采样，不声明图像。
// 波高与传播速度：逐次模拟写回，供下一帧继续，因此不能每帧清除。
layout(rgba16f) uniform image2D omniWaveSim; // 本次模拟的中间场：红绿两通道存压强与压强速度。
layout(rgba16f) uniform image2D omniWaveSim2; // 上一次模拟的成品场：红绿存压强与速度，蓝绿存两个方向的坡度。
// 跨帧状态：一张四乘一的图像代替 Eclipse 的共享缓冲，每个纹素存一组数据。
layout(rgba32f) uniform image2D omniWaveState; // 零号相机位置、一号网格原点、二号累加器与时刻、三号位移与初始化标记。

// 读跨帧状态：把四组数据各拆成一个函数，调用处只看名字就知道取的是哪一组。
vec4 waveStateCamera(){ return imageLoad(omniWaveState, ivec2(0, 0)); } // 上一帧相机位置，用来估玩家速度。
vec3 waveStateOrigin(){ return imageLoad(omniWaveState, ivec2(1, 0)).xyz; } // 模拟网格中心的绝对世界位置。
vec4 waveStateMisc(){ return imageLoad(omniWaveState, ivec2(2, 0)); } // 横纵位移累加、上次模拟时刻、扰动半径。
ivec2 waveStateOffset(){ return ivec2(imageLoad(omniWaveState, ivec2(3, 0)).xy); } // 本次模拟要施加的整数格平移。
float waveStateReady(){ return imageLoad(omniWaveState, ivec2(3, 0)).z; } // 初始化标记：零表示还没跑过第一次模拟。
#else // 片元阶段：把两张成品图像当成普通纹理采样，取法线、原点与坡度。
uniform sampler2D omniWaveSim2Tex; // 成品模拟场，蓝绿通道是坡度。
uniform sampler2D omniWaveStateTex; // 跨帧状态图像，取网格原点。
#endif // 计算与片元分支结束。

// 取模拟出的波法线：把世界位置映射到模拟场坐标，越界或水面不朝上时返回零权重。
// 参数 `fieldTex` 是成品模拟场，`stateTex` 是状态图像（拿网格原点），`worldPos` 是水面片元的世界位置，
// `upness` 是水面朝向与世上方向的夹角；返回前三个分量是切线空间法线、第四个分量是混入权重。
vec4 omniWaveSimNormal(sampler2D fieldTex, sampler2D stateTex, vec3 worldPos, float upness){
	if (abs(upness) < 0.5) return vec4(0.0, 0.0, 1.0, 0.0); // 侧壁与底面不做模拟造型，省下采样。
	vec2 origin = texelFetch(stateTex, ivec2(1, 0), 0).xy; // 上次模拟网格中心的水平位置。
	vec2 uv = (worldPos.xz - origin) * OMNI_WAVE_SIM_NORMAL_SCALE; // 世界位置映射到以网格中心为原点的坐标。
	if (length(uv) >= 0.5) return vec4(0.0, 0.0, 1.0, 0.0); // 超出模拟覆盖范围就不参与，边缘不会硬接。
	vec4 field = texture(fieldTex, uv + 0.5); // 采样成品场，蓝绿通道即两个方向的坡度。
	vec3 normal = normalize(vec3(field.z, field.w, 1.0)); // 用坡度拼出切线空间法线，竖直分量为一。
	float weight = clamp(OMNI_WAVE_SIM_STRENGTH * sqrt(sqrt(abs(field.x))), 0.0, 1.0); // 压强越大权重越大，取四次方根压平曲线。
	return vec4(normal, weight); // 法线与权重一起交回调用方。
}
#endif // 波浪模拟整段结束。
#endif // OMNI_RENDER_WATER_WAVESIM_INCLUDED
