/*
效果文件 `effects/shared/water/rain.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shared/water/rain.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_WATER_RAIN_INCLUDED
#define OMNI_WATER_RAIN_INCLUDED
/*
雨点涟漪：下雨时在水面叠一层随时间滚动的涟漪纹理，并按湿度与积水模式给出法线扰动。
来源 iterationT `Ripple.glsl`。
调用位置：由 `effects/water/water.glsl` 引入；水面材质取法线时调用 `GetRainNormal`。
可复制示例：`vec2 rainNormal = GetRainNormal(worldPos, strength, wet);`
设计原因与取舍：涟漪是与基础波浪独立的一层，单独成文件后可按“下雨”这个主体查找；
    是否强制局部无降水、积水模式各档的差别都写在函数里，选项仍在入口定义。
*/
// 雨雾高光与雨点动画的纯公式放在通用库。
// 材质与水洼选项由共享表面主体统一定义。
#include "/effects/shared/surface.glsl"
#include "/omni-gfx/water.glsl"
// 雨纹动画的对比度重整属于天气效果，本文件只把它接到水面纹理。
#include "/omni-gfx/weather/rain.glsl"
// 降雨、雪天与干燥群系标记由绑定层整理，涟漪只接收普通数值。
#include "/bind/weather.glsl"
// 雨点动画的当前帧由累计秒数换算。
#include "/bind/time.glsl"
// --- 雨点涟漪：用三张动画贴图叠出雨滴落点，供水面与地表使用 ---
// 三层动画贴图越大越散开，用降雨强度与降雪、无降水标记调制，雪天与干燥群系不出现雨点。
// 为什么用三重噪声：单层噪声太规则，三层不同缩放叠加后落点更自然。

// 雨雾高光调制：三层噪声叠加后归一，让雨中的高光随时间轻微变化。
float GetModulatedRainSpecular(vec3 pos){
	return ogxRainSpecular(pos, noisetex); // 三层噪声公式在通用库。
}

// 读一张雨点动画贴图并转成带符号的法线，指数控制边缘锐度。
vec2 GetRainAnimationTex(sampler2D texSampler, vec2 coord, float rp){
	return ogxRainAnimationTex(texSampler, coord, rp); // 通用天气模块的雨纹重整。
}

// 雨点法线：按动画相位在贴图上采样，三层按降雨强弱叠加。
// 为什么用整数帧取模：让动画按固定帧率推进，避免不同刷新设备上速度不一致。
// 末尾再按「雨点涟漪强度」与「雨点涟漪对比」两个选项统一缩放，两个默认都为一、画面不变。
vec2 GetRainNormal(vec3 pos, float strength, inout float wet){
	pos.xyz *= 0.5; // 缩放坐标，让落点更大。
	OmniWeather weather = bind_weather(); // 本帧的降雨与群系标记只读一次。
	#ifdef OMNI_DISABLE_LOCAL_PRECIPITATION // 强制局部无降水时只看整体降雨。
		strength *= weather.rain; // 只乘降雨强度。
	#else // 默认按所在群系的下雪与无降水标记调制。
		strength *= weather.rain * (1.0 - weather.snowy) * (1.0 - weather.noPrecipitation); // 雪天或干燥群系雨点减弱。
	#endif

	#if OMNI_PUDDLE_MODE == 0 // 模式零：不出雨点，强度直接归零。
		strength = 0.0; // 后面乘出零向量，等于关闭涟漪。
	#endif

	float frame = fract(floor(bind_time().seconds * 60.0) / 60.0); // 当前动画帧，按每秒六十帧取整。
	vec2 coord = vec2(pos.x, fract(pos.z / 60.0) - frame); // 动画沿一个轴滑动。

	float wet2 = wet * wet; // 湿润度平方。
	float rp = 2.0 - (wet2 * wet2) * 1.2; // 越湿边缘越锐。

	vec2 n1 = GetRainAnimationTex(gaux1, coord, rp); // 第一张动画贴图。
	vec2 n2 = GetRainAnimationTex(gaux2, coord, rp); // 第二张动画贴图。
	vec2 n3 = GetRainAnimationTex(gaux3, coord, rp); // 第三张动画贴图。

	pos.x -= frameTimeCounter * 0.5; // 沿一个轴漂移，落点缓慢移动。
	float downfall = textureLod(noisetex, pos.xz * 0.0025, 0.0).w; // 读噪声得到落点密度。
	downfall = saturate(downfall - 0.25); // 留一个阈值，稀疏区域没有雨点。
	#if OMNI_PUDDLE_MODE == 3 // 模式三「仅全湿润」：整片湿表面均匀铺满，不做稀疏判断。
		downfall = 1.0; // 三层动画全部出现，涟漪覆盖整个表面。
	#endif

	vec2 n = n1; // 第一层总是有。
	n += n2 * saturate(downfall * 2.0); // 密度中等时叠第二层。
	n += n3 * saturate(downfall * 2.0 - 1.0); // 密度高时才叠第三层。

	float lod = dot(fwidth(pos.xz), vec2(1.0)); // 屏幕上的坐标变化量，用来按距离衰减。

	n /= lod * 5.0 + 1.0; // 越远越平，避免远处闪烁。
	n *= strength * OMNI_RAIN_RIPPLE_STRENGTH; // 乘降雨强度与「雨点涟漪强度」选项。
	n = sign(n) * pow(abs(n), vec2(OMNI_RAIN_RIPPLE_CONTRAST)); // 「雨点涟漪对比」：对幅度取幂并保留符号，指数大于一让亮圈更锐、圈外更平；指数为一原样返回。
	#if OMNI_PUDDLE_MODE == 2 // 模式二「仅水洼」：只在低洼处出现。
		float puddleNoise = textureLod(noisetex, pos.xz * 0.02, 0.0).b; // 水洼形状噪声，值越低表示地势越低。
		n *= OmniPuddleCoverage(wet, puddleNoise); // 用统一的水洼覆盖公式，`OMNI_PUDDLE_SIZE` 越大水洼越大越连片，只在低洼处出水洼。
	#endif

	wet = saturate(mix(downfall, wet, 1.0 - 0.4 * saturate(strength))); // 湿润度向落点密度靠拢，降雨越强越明显。

	return n; // 返回雨点法线。
}

#endif // OMNI_WATER_RAIN_INCLUDED
