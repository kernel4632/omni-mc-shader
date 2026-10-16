/*
时间噪声：照 iterationT `Lib/BasicFounctions/TemporalNoise.glsl` 一比一移植，给每个像素每帧不同的抖动值。
调用位置：绘制主体在 `common/uniforms.glsl`、`common/math.glsl` 之后引入，只能用在片元阶段。
可复制示例：
    `vec2 noise = BlueNoiseTemporal();`    每帧变化的二维蓝噪声，光线步进起点抖动用
    `float dither = BayerTemporal();`      每帧变化的拜尔抖动
设计原因与取舍：
    蓝噪声来自六十四像素的 `noisetex`，每帧按黄金比和塑料数平移，配合时间抗锯齿把噪点平均掉。
    原名拼写 `Temproal` 按移植合同改为 `Temporal`，其余写法不变。
    函数直接读 `gl_FragCoord`，所以不能在顶点或计算阶段调用。
*/
#ifndef OMNI_NOISE_INCLUDED // 只引入一次。
#define OMNI_NOISE_INCLUDED // 置上标记。

// 噪声贴图来自加载器输入声明，拜尔矩阵来自共用计算，这里自己先引入这两份。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"

// 不随时间变化的二维蓝噪声，按像素位置平铺。
vec2 BlueNoise(){
	return texelFetch(noisetex, ivec2(gl_FragCoord.xy) % 64, 0).xy; // 贴图边长六十四，取余后平铺。
}

// 每帧平移的二维蓝噪声，六十四帧一循环。
vec2 BlueNoiseTemporal(){
	return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy) % 64, 0).xy + vec2(goldenRatio, plasticRatio) * vec2(frameCounter % 64)); // 两个方向用不同无理数步长，避免重复图案。
}

// 每帧平移的拜尔抖动，一百二十八帧一循环。
float BayerTemporal(){
	return fract(bayer64(gl_FragCoord.xy) + goldenRatio * float(frameCounter % 128)); // 黄金比步长让相邻帧尽量不同。
}
#endif // 文件守卫结束。
