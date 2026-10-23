/*
波浪模拟计算入口：三个计算阶段在模拟场图像上注入、传播并求坡度，供水面片元读取。
来源：Eclipse `dimensions/prepare.csh`、`prepare1.csh`、`prepare2.csh`，逐行搬运；把原来分在四个程序里的
  状态维护合进本文件的 `prepare` 一个程序，跨帧状态改存一张四乘一图像（Eclipse 用共享缓冲）。
调用位置：各维度 `prepare.csh`、`prepare1.csh`、`prepare2.csh` 入口定义 `OMNI_COMPUTE` 与对应阶段宏后引入
  本文件；入口由 `rendering/programs.json` 的 `compute` 段生成，顺序固定为 prepare、prepare1、prepare2。
可复制示例：入口写 `#define OMNI_COMPUTE 1`、`#define OMNI_WAVE_SIM_SPREAD 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/watersim.glsl"`；选项与图像声明来自 `effects/water/wavesim.glsl`。
设计原因与取舍：
  一、三个阶段各自一个程序，是因为传播阶段要跨整个图像读邻居，跨工作组的同步只能靠分立派发，不能只靠工作组屏障；
  二、`prepare` 每帧都跑，但只有跨过模拟间隔（每秒六十次）才真正推进网格；同一帧里 `prepare` 先更新网格原点，
     后面两个阶段用更新后的网格工作，与 Eclipse 的程序顺序一致；
  三、`!OMNI_WAVE_SIM_ON` 时三个程序的 `main` 都保持空实现，不用额外的程序开关，选项关闭时派发的是空任务；
  四、边界一律夹紧到图像内侧一圈，避免在边缘读出不存在的邻居。
*/
#ifndef OMNI_WATER_SIM_INCLUDED // 只引入一次，避免阶段宏重复展开。
#define OMNI_WATER_SIM_INCLUDED // 置上标记。

// 加载器输入：相机位置、帧时间、眼睛介质等由统一声明提供。
#include "/common/uniforms.glsl"
// 选项、常量、图像与跨帧状态访问都来自效果文件，计算与采样共用同一份定义。
#include "/rendering/water/wavesim.glsl"

#ifdef OMNI_COMPUTE // 只有计算阶段编译下面的入口。
#ifdef OMNI_WAVE_SIM_ON // 选项关闭或缺能力时，三个程序的 main 都是空的。

// 边界下标：邻居与采样点一律夹到内侧一圈，边缘读不出界。
ivec2 omniWaveSimClamp(ivec2 c){ return clamp(c, ivec2(1), ivec2(OMNI_WAVE_SIM_RES - 1)); } // 夹到 [1, 边长-1]。

// 一次模拟推进：读入压强与压强速度，按波动方程更新，再按距离与朝向做阻尼。
// 参数 `pressure`、`pVel` 是当前点的状态，四个邻居压强是 `pDown/pLeft/pRight/pUp`，`dist` 是到网格中心的距离。
// 返回横纵两个分量分别是更新后的压强与压强速度；这样传播与求坡度两个阶段共用同一套推进公式，不会各写一份。
vec2 omniWaveSimStep(float pressure, float pVel, float pDown, float pLeft, float pRight, float pUp, float dist){
	float d = OMNI_WAVE_SIM_DELTA; // 时间步长，越大传播越快。
	pVel += d * (-2.0 * pressure + pRight + pLeft) / 4.0; // 横向波动：拉向左右邻居的平均。
	pVel += d * (-2.0 * pressure + pUp + pDown) / 4.0; // 纵向波动：拉向上下邻居的平均。
	pressure += d * pVel; // 压强按速度前进。
	pVel -= 0.0014 * d * pressure; // 弹簧项：让波纹像水波而不是声波。
	pVel *= 1.0 - 0.006 * d; // 速度阻尼：没人扰动时最终平静。
	float distFade = smoothstep(0.49 * float(OMNI_WAVE_SIM_RES), 0.25 * float(OMNI_WAVE_SIM_RES), dist); // 近中心满值、向外淡出。
	pressure *= 0.985 * distFade; // 压强阻尼，避免越积越大。
	pVel *= distFade; // 速度同样向外淡出，边缘不反弹。
	return vec2(pressure, pVel); // 交回更新后的状态。
}

// 玩家扰动：站在水面上时，在网格中心给一圈与移动速度相关的凸起。
// `dist` 是到中心的距离，`roundSize` 是扰动半径；返回要叠加到压强上的量。
float omniWaveSimInjection(float dist){
	if (isEyeInWater != 1) return 0.0; // 眼睛不在水里就不加扰动，近似代表「没站在水面上」。
	float roundSize = max(imageLoad(omniWaveState, ivec2(2, 0)).w, 1.0); // 扰动半径，未初始化时兜到一。
	return smoothstep(roundSize, 0.7 * roundSize, dist); // 半径内向外递减的平滑凸起。
}
#endif // 波浪模拟开关结束。
#endif // 计算阶段结束。

// --- 阶段一 prepare：维护跨帧状态，并在跨过模拟间隔时更新网格原点与平移量 ---
#ifdef OMNI_COMPUTE
#ifdef OMNI_WAVE_SIM_PREPARE
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in; // 单线程，只改状态图像，不需要并行。
const ivec3 workGroups = ivec3(1, 1, 1); // 只派发一个线程。

// 状态图像四组数据：零号相机、一号网格原点、二号累加器与时刻、三号平移与初始化标记。
void main(){
#ifdef OMNI_WAVE_SIM_ON // 关闭时保持空实现。
	vec4 misc = waveStateMisc(); // 读累加器、时刻与半径。
	bool ready = waveStateReady() > 0.5; // 是否已经跑过第一次模拟。
	vec3 camera = cameraPosition; // 本帧相机绝对位置。

	if (abs(frameTimeCounter - misc.z) > OMNI_WAVE_SIM_FRAMETIME) { // 只有跨过模拟间隔才推进网格。
		vec3 origin = ready ? waveStateOrigin() : camera; // 没跑过时把原点直接设成本帧相机，避免首帧巨大位移。
		vec2 movement = camera.xz - origin.xz; // 自上次模拟以来玩家的水平位移。
		vec2 accum = misc.xy + OMNI_WAVE_SIM_MOVE_SCALE * movement; // 位移折算成纹素并累加，抵消观察者移动。
		ivec2 offset = ivec2(trunc(accum)); // 取整数部分才是整格平移，采样只会落在整纹素上。
		if (offset.x != 0 || offset.y != 0) accum -= vec2(offset); // 小数部分留下次继续累加。
		imageStore(omniWaveState, ivec2(3, 0), vec4(vec2(offset), 1.0, 0.0)); // 记下本次平移与「已初始化」标记。

		float roundSize = misc.w; // 扰动半径，默认保留上次的值。
		if (isEyeInWater == 1) { // 在水里才更新半径，近似代表站在水面上。
			vec2 velocity = (camera.xz - waveStateCamera().xz) / max(frameTime, 1.0e-4); // 每秒水平位移。
			roundSize = 10.0 + 10.0 * smoothstep(0.1, 13.0, length(velocity)); // 动得越快，扰动范围越大。
		}
		imageStore(omniWaveState, ivec2(2, 0), vec4(accum, frameTimeCounter, roundSize)); // 写回累加器、时刻与半径。
		imageStore(omniWaveState, ivec2(1, 0), vec4(camera, 1.0)); // 更新网格原点为本帧相机。
	}
	imageStore(omniWaveState, ivec2(0, 0), vec4(camera, 1.0)); // 每帧记下相机，供下一帧估速度。
#endif // 波浪模拟开关结束。
}
#endif // prepare 阶段结束。
#endif // 计算阶段结束。

// --- 阶段二 prepare1 传播：按平移量对齐上一次成品场，推进后写入中间场 ---
#ifdef OMNI_COMPUTE
#ifdef OMNI_WAVE_SIM_SPREAD
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in; // 每工作组盖三十二乘三十二块。
const ivec3 workGroups = ivec3(32, 32, 1); // 工作组数正好盖满整张图。

// 传播主函数：对齐旧场后推进，并把结果写进中间场。
void main(){
#ifdef OMNI_WAVE_SIM_ON // 关闭时保持空实现。
	if (abs(frameTimeCounter - waveStateMisc().z) <= OMNI_WAVE_SIM_FRAMETIME) return; // 没跨过模拟间隔就不推进。

	ivec2 imgCoord = ivec2(gl_GlobalInvocationID.xy); // 当前纹素。
	float dist = length(vec2(imgCoord) - 0.5 * float(OMNI_WAVE_SIM_RES)); // 到网格中心的距离。
	if (dist >= float(OMNI_WAVE_SIM_RES)) return; // 圆形范围外不参与。

	ivec2 sampled = omniWaveSimClamp(imgCoord - waveStateOffset()); // 按平移量对齐上一次的成品场。
	vec2 state = imageLoad(omniWaveSim2, sampled).xy; // 该点的压强与压强速度。
	float pDown = imageLoad(omniWaveSim2, omniWaveSimClamp(sampled + ivec2(0, -1))).x; // 下邻居压强。
	float pLeft = imageLoad(omniWaveSim2, omniWaveSimClamp(sampled + ivec2(-1, 0))).x; // 左邻居压强。
	float pRight = imageLoad(omniWaveSim2, omniWaveSimClamp(sampled + ivec2(1, 0))).x; // 右邻居压强。
	float pUp = imageLoad(omniWaveSim2, omniWaveSimClamp(sampled + ivec2(0, 1))).x; // 上邻居压强。

	vec2 stepped = omniWaveSimStep(state.x, state.y, pDown, pLeft, pRight, pUp, dist); // 推进一步。
	float pressure = stepped.x + omniWaveSimInjection(dist); // 叠加玩家扰动。

	imageStore(omniWaveSim, imgCoord, vec4(pressure, stepped.y, 0.0, 0.0)); // 中间场只存压强与速度。
#endif // 波浪模拟开关结束。
}
#endif // prepare1 阶段结束。
#endif // 计算阶段结束。

// --- 阶段三 prepare2 求坡度：读中间场推进，写入成品场并带上两个方向的坡度 ---
#ifdef OMNI_COMPUTE
#ifdef OMNI_WAVE_SIM_GRADIENT
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in; // 与传播阶段相同的覆盖方式。
const ivec3 workGroups = ivec3(32, 32, 1); // 盖满整张图。

// 坡度主函数：用左右、上下邻居的压强差近似压强梯度，供片元拼出波法线。
void main(){
#ifdef OMNI_WAVE_SIM_ON // 关闭时保持空实现。
	if (abs(frameTimeCounter - waveStateMisc().z) <= OMNI_WAVE_SIM_FRAMETIME) return; // 没跨过模拟间隔就不推进。

	ivec2 imgCoord = ivec2(gl_GlobalInvocationID.xy); // 当前纹素。
	float dist = length(vec2(imgCoord) - 0.5 * float(OMNI_WAVE_SIM_RES)); // 到网格中心的距离。
	if (dist >= float(OMNI_WAVE_SIM_RES)) return; // 圆形范围外不参与。

	ivec2 center = omniWaveSimClamp(imgCoord); // 本阶段不做平移，直接读中间场的同一点。
	vec2 state = imageLoad(omniWaveSim, center).xy; // 该点压强与速度。
	float pDown = imageLoad(omniWaveSim, omniWaveSimClamp(center + ivec2(0, -1))).x; // 下邻居压强。
	float pLeft = imageLoad(omniWaveSim, omniWaveSimClamp(center + ivec2(-1, 0))).x; // 左邻居压强。
	float pRight = imageLoad(omniWaveSim, omniWaveSimClamp(center + ivec2(1, 0))).x; // 右邻居压强。
	float pUp = imageLoad(omniWaveSim, omniWaveSimClamp(center + ivec2(0, 1))).x; // 上邻居压强。

	vec2 stepped = omniWaveSimStep(state.x, state.y, pDown, pLeft, pRight, pUp, dist); // 推进一步，和传播阶段同一套公式。
	float pressure = stepped.x + omniWaveSimInjection(dist); // 叠加玩家扰动。

	float gradX = (pRight - pLeft) / 2.0; // 横向压强梯度，就是这一点的横向坡度。
	float gradZ = (pUp - pDown) / 2.0; // 纵向压强梯度。
	imageStore(omniWaveSim2, imgCoord, vec4(pressure, stepped.y, gradX, gradZ)); // 成品场：压强、速度、两个坡度。
#endif // 波浪模拟开关结束。
}
#endif // prepare2 阶段结束。
#endif // 计算阶段结束。
#endif // 文件守卫结束。
