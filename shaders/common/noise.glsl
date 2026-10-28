/*
时间噪声：照 iterationT `Lib/BasicFounctions/TemporalNoise.glsl` 一比一移植，给每个像素每帧不同的抖动值。
调用位置：绘制主体在 `common/uniforms.glsl`、`common/math.glsl` 之后引入，主要用在片元阶段。
可复制示例：
    `vec2 noise = BlueNoiseTemporal();`    每帧变化的二维蓝噪声，光线步进起点抖动用
    `float dither = BayerTemporal();`      每帧变化的拜尔抖动
设计原因与取舍：
    蓝噪声来自六十四像素的 `noisetex`，每帧按黄金比和塑料数平移，配合时间抗锯齿把噪点平均掉。
    原名拼写 `Temproal` 按移植合同改为 `Temporal`，其余写法不变。
    原程序的函数直接读 `gl_FragCoord`，只有片元阶段存在这个内建量；顶点与几何阶段也会整段编译本文件，
    所以这里用一个统一像素坐标宏：片元阶段就是 `gl_FragCoord.xy`，其它阶段取常量零。这样同名的三个函数
    在任何阶段都能编译，而它们在顶点阶段本来就不会被调用，输出不受影响。
*/
#ifndef OMNI_NOISE_INCLUDED // 只引入一次。
#define OMNI_NOISE_INCLUDED // 置上标记。

// 噪声贴图来自加载器输入声明，拜尔矩阵来自共用计算，这里自己先引入这两份。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 采样算法放在通用库，本文件只把加载器纹理、像素坐标和帧号传进去。
#include "/omni-gfx/sampling.glsl"
// 三角噪声与雾噪声在生成库，宿主兼容层直接引用。
#include "/omni-gfx/noise.glsl"

// 统一像素坐标：片元阶段用真实片元坐标，其它阶段取零；见文件头的取舍说明。
#ifdef OMNI_FRAGMENT
	#define OMNI_PIXEL gl_FragCoord.xy // 片元阶段：真实像素坐标。
#else
	#define OMNI_PIXEL vec2(0.0) // 顶点、几何与计算阶段：本文件不在这里取噪声，给一个可编译的常量。
#endif

// --- Eclipse 抖动与采样兼容层：参考函数自己取像素坐标、时间与导数 ---
#ifdef OMNI_FRAGMENT
// 四乘四拜尔矩阵，参考直接读 gl_FragCoord。
float bayerDither(){ return ogxBayer4Dither(gl_FragCoord.xy); }
// 三角白噪声，参考直接读当前帧时间。
float triangWhiteNoise(vec2 n){ return ogxTriangleNoise(n, frameTimeCounter); }
#endif // 片元阶段结束。


// 参考签名兼容层：iterationT 的 `Get3DNoise` 直接读全局噪声贴图。
float Get3DNoise(vec3 position){ return ogxFogNoise(position, noisetex); }

// 参考的一维白噪声：把输入扩成两个不同频率再走二维哈希。
float rand(float co){ return ogxWhiteNoise(vec2(co, co * 2.0)); }

// 不随时间变化的二维蓝噪声，按像素位置平铺。
vec2 BlueNoise(){
	return ogxBlueNoise(noisetex, ivec2(OMNI_PIXEL)); // 传纹理和坐标，库负责取模平铺。
}

// 每帧平移的二维蓝噪声，六十四帧一循环。
vec2 BlueNoiseTemporal(){
	return ogxBlueNoiseTemporal(noisetex, ivec2(OMNI_PIXEL), frameCounter); // 帧号交给库做时间偏移。
}

// 每帧平移的拜尔抖动，一百二十八帧一循环。
float BayerTemporal(){
	return ogxBayerTemporal(ivec2(OMNI_PIXEL), frameCounter); // 拜尔矩阵与帧偏移都在库里。
}
// 参考签名兼容层：参考的采样函数不带参数，直接取当前像素与帧号。
vec2 BlueNoiseTemproal(){ return BlueNoiseTemporal(); }
float BayerTemproal(){ return BayerTemporal(); }
#endif // 文件守卫结束。
