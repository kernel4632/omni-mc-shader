/*
镜头眩光与光斑：沿光线方向拉出细长亮纹，再叠一组鬼影、光环与散点。
来源 iterationT `LensGlareFlare.glsl`。
调用位置：由 `effects/lens/lens.glsl` 引入；合成阶段调用 `LensFlare`。
可复制示例：`vec3 glare = LensFlare();`
设计原因与取舍：眩光与光斑共用同一批光点和色散取样，合在一个文件；两者各自带开关，关闭时整段不编译。
*/
#ifndef OMNI_LENS_GLARE_INCLUDED
#define OMNI_LENS_GLARE_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 镜头眩光与光斑 ---
// 只在开启眩光或光斑时编译这一段。
#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE
	#define ORB_FLARE_COUNT	6.0 // 一组鬼影包含几个圆形光斑。
	#define DISTORTION_BARREL 1.0 // 桶形畸变强度，让鬼影沿弧线排布。

	// 求一个偏移向量在桶形畸变后的方向，用于把鬼影沿弧线排列。
	vec2 GetDistOffset(vec2 uv, vec2 pxoffset){
		vec2 tocenter = uv.xy; // 当前点到中心的方向。
		vec3 prep = normalize(vec3(tocenter.y, -tocenter.x, 0.0)); // 与中心方向垂直的轴。
		float angle = length(tocenter.xy) * 2.221 * DISTORTION_BARREL; // 旋转角随距离增大。
		vec3 oldoffset = vec3(pxoffset, 0.0); // 把偏移抬到三维。
		vec3 rotated = oldoffset * cos(angle) + cross(prep, oldoffset) * sin(angle) + prep * dot(prep, oldoffset) * (1.0 - cos(angle)); // 绕轴旋转。
		return rotated.xy; // 取回二维偏移。
	}

	// 画一个带色散的软光点：红绿蓝三个通道沿鬼影方向错开一点，得到彩色边缘。
	vec3 flare(vec2 uv, vec2 pos, float dist, float chromaOffset, float size){
		pos = GetDistOffset(uv, pos); // 先对鬼影位置做桶形畸变。
		float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) *( 1.0 / (size * 2.0)), 0.0) * 0.85; // 红色通道。
		float g = max(0.01 - pow(length(uv +  dist                 * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿色通道。
		float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝色通道。
		return vec3(r, g, b); // 返回带色散的光点颜色。
	}

	// 画一串沿鬼影方向排列的圆形光斑，颜色从暖到冷渐变。
	vec3 orb(vec2 uv, vec2 pos, float dist, float size){
		vec3 c = vec3(0.0); // 累加结果。
		for (float i = 0.0; i < ORB_FLARE_COUNT; i++){ // 逐个光斑。
			float j = i + 1; // 从一起数的序号。
			float offset = j / (j + 0.1); // 这个光斑在鬼影方向上的位置。
			float colOffset = j / ORB_FLARE_COUNT * 0.5; // 颜色偏移。
			float ss = size / (j + 1.0); // 越靠后的光斑越小。
			c += flare(uv, pos, dist + offset, ss * 2.0, ss) * vec3(1.0 - colOffset, 1.0, 0.5 + colOffset) * j; // 累加并染色放大。
		}
		c += flare(uv, pos, dist + 0.8, 0.05, 3.0 * size) * 0.5; // 末尾再补一个大的柔和光斑。
		return c; // 返回光斑颜色。
	}

	// 画一个环状光环，三个通道同样做色散。
	vec3 ring(vec2 uv, vec2 pos, float dist, float chromaOffset, float blur){
		vec2 uvd = uv * length(uv); // 把坐标按到中心距离放大，得到环而不是点。
		float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红色通道。
		float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd +  dist                 * pos), blur)), 0.0) * 1.0; // 绿色通道。
		float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝色通道。
		return vec3(r, g, b); // 返回光环颜色。
	}

	// 镜头光斑主入口：按太阳在屏幕上的位置铺开眩光与鬼影，并按太阳可见度与雾浓淡衰减。
	// 输出按管线编码，写进三号画面，稍后由八号与十四号阶段叠加。
	vec3 LensFlare(){
		vec3 lf = vec3(0.0); // 累加结果。
		vec2 coord = texCoord - 0.5; // 当前点相对中心。
		vec2 sunPos = sunCoord - 0.5; // 太阳相对中心。
		coord.x *= aspectRatio; // 按宽高比修正成圆。
		sunPos.x *= aspectRatio; // 太阳位置同样修正。
		float fovFactor = max(gbufferProjection[1][1], 2.0); // 由投影矩阵估计视场，给一个下限。
		#ifdef OMNI_LENS_GLARE // 眩光：沿光线方向拉出细长亮纹。
			vec2 v = coord - sunPos; // 当前点到太阳的方向。
			float dist = length(v); // 距离。
			float gDist = dist * 13.0 / fovFactor; // 按视场归一化。
			float phase = atan2(v) + 0.131; // 方向角加一个固定偏移。
			float gl = 2.0 - saturate(gDist) + sin(phase * 12.0) * saturate(gDist * 2.5 - 0.2); // 细长亮纹。
			gl = gl * gl; // 平方加强。
			gDist = gDist * gDist; // 距离平方。
			gl *= 8e-5 / (gDist * gDist); // 按距离衰减。
			gl = min(gl, 200.0); // 设上限避免过亮。
			lf += vec3(gl * OMNI_GLARE_BRIGHTNESS); // 按眩光亮度累加。
		#endif
		#ifdef OMNI_LENS_FLARE // 光斑：一组鬼影、两个光环和若干散点。
			float size = 0.5 * fovFactor; // 光斑整体大小。
			vec3 fl = vec3(0.0); // 光斑累加。
			fl += orb(coord, sunPos, 0.0, size * 0.01) * 0.1; // 圆形鬼影。
			fl += ring(coord, sunPos,  1.0, 0.02, 1.4) * 0.01; // 远端光环。
			fl += ring(coord, sunPos, -1.0, 0.02, 1.4) * 0.01; // 近端光环。
			fl += flare(coord, sunPos, -2.00, 0.05, size * 0.05) * 0.5; // 一抹大鬼影。
			fl += flare(coord, sunPos, -0.90, 0.02, size * 0.03) * 0.3; // 散点。
			fl += flare(coord, sunPos, -0.70, 0.01, size * 0.06) * 0.5; // 散点。
			fl += flare(coord, sunPos, -0.55, 0.02, size * 0.02) * 0.2; // 散点。
			fl += flare(coord, sunPos, -0.35, 0.02, size * 0.04) * 0.7; // 散点。
			fl += flare(coord, sunPos, -0.25, 0.01, size * 0.15) * vec3(0.3, 0.4, 0.38); // 偏青的大鬼影。
			fl += flare(coord, sunPos, -0.25, 0.02, size * 0.08) * 0.2; // 散点。
			fl += flare(coord, sunPos,  0.05, 0.01, size * 0.03) * 0.1; // 散点。
			fl += flare(coord, sunPos,  0.30, 0.02, size * 0.20) * vec3(0.2, 0.18, 0.14); // 偏暖的鬼影。
			fl += flare(coord, sunPos,  1.20, 0.03, size * 0.10) * 0.2; // 散点。
			lf += fl * (OMNI_FLARE_BRIGHTNESS * 0.3); // 按光斑亮度累加。
		#endif
		lf *= colorSunlight * (sunVisibility * saturate(exp2(1.0 - OMNI_VFOG_DENSITY * 20.0)) / MAIN_OUTPUT_FACTOR); // 按阳光颜色、可见度与雾浓淡衰减。
		return LinearToCurve(lf); // 按管线编码返回。
	}
#endif // 眩光与光斑结束。

#endif // 文件守卫结束。
