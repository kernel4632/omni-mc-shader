/*
水下焦散：从七号画面的波法线里读出水面波纹，按折射后的阳光在波纹上找汇聚点，算出焦散花纹。
来源 iterationT 阳光在水体里的焦散段。
调用位置：由 `effects/shadow/shadow.glsl` 引入；合成阶段算水体焦散时调用 `CalculateWaterCaustics`。
可复制示例：`float caustics = CalculateWaterCaustics(worldPos, shadowLightVector);`
设计原因与取舍：焦散要用阴影侧的光方向与波法线，所以跟着阴影文件；波法线从七号画面取，不重算波浪。
*/
#ifndef OMNI_WATER_CAUSTICS_INCLUDED
#define OMNI_WATER_CAUSTICS_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 焦散法线：从七号画面的方块里读出波法线 ---
// 七号画面左下角最多五百像素见方，存的是水面波法线；读取时用折射方向把世界位置投到这个方块里。
// 为什么先按折射方向移动坐标：光线进入水面会弯折，直接用世界横纵坐标会读到错误的波法线。
vec3 GetWavesNormalFromTex(vec3 position, vec3 shadowLightVector){
	const float maxCausticsNormalHeight = CAUSTICS_TEX_RESOLUTION; // 方块边长上限，来自内部常数。

	vec2 coord = position.xz; // 先取水平坐标。
	vec3 lightVector = refract(shadowLightVector, vec3(0.0, 1.0, 0.0), 1.0 / WATER_REFRACT_IOR); // 阳光按水面折射率弯折得到光线方向。
	coord.x += position.y * lightVector.x / lightVector.y; // 按高度沿光线横移横坐标。
	coord.y += position.y * lightVector.z / lightVector.y; // 按高度沿光线横移纵坐标。

	coord *= 0.02; // 缩到波法线图的空间尺度。
	coord = fract(coord); // 平铺到零到一。

	coord *= pixelSize * min(screenSize.y, maxCausticsNormalHeight); // 折算成方块里的像素坐标。

	vec3 normal; // 解出的波法线。
	normal.xyz = DecodeNormal(textureLod(colortex7, coord, 0.0).xy); // 从方块里读八面体编码法线。

	return normal; // 返回世界空间波法线。
}

// --- 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹 ---
// 输入是相机相对世界位置；把阳光按水面折射后向水下投，用波面法线判断光线是否汇聚，汇聚处更亮。
// 为什么用九次采样：三乘三抖动采样已经能把焦散花纹的噪点压到可接受，再多收益不明显。
float CalculateWaterCaustics(vec3 worldPos, vec3 shadowLightVector){
	worldPos.xyz += cameraPosition; // 相机相对世界位置补上相机位置，换成绝对坐标。

	vec2 dither = BlueNoiseTemporal(); // 每帧变化的抖动，打散采样花纹。

	vec3 lookupCenter = worldPos + vec3(0.0, 1.0, 0.0); // 从水面上方一米处开始找波面。

	vec3 lightVector = refract(shadowLightVector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
	vec3 depthBias = vec3(worldPos.y * lightVector.x, 0.0, worldPos.y * lightVector.z) / lightVector.y; // 按水深沿光线偏移，找到水底对应位置。

	float caustics = 0.0; // 累计焦散强度。

	for (float i = -1.0; i <= 1.0; i++){ // 三乘三抖动采样。
		for (float j = -1.0; j <= 1.0; j++){
			vec2 offset = dither + vec2(i, j); // 当前采样偏移。

			vec3 lookupPoint = lookupCenter; // 这一处的波面查询点。
			lookupPoint.xz += offset * 0.1; // 按偏移横移。

			vec3 wavesNormal = GetWavesNormalFromTex(lookupPoint, shadowLightVector).xzy; // 读取波法线并换到竖直轴朝上的坐标。

			vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal.xyz, 1.0); // 竖直光线被波面折射后的方向。
			vec3 collisionPoint = lookupPoint - refractVector / refractVector.y; // 光线与水平面的交点。
			collisionPoint -= worldPos; // 相对当前位置。

			float dist = dot(collisionPoint, collisionPoint) * 7.1; // 交点距离的平方，放大差距。

			caustics += 1.0 - saturate(dist * 7.0); // 交点越近越亮，模拟光线汇聚。
		}
	}

	float causticsFinal = mix(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(isEyeInWater)); // 拼成焦散亮度，水下再往全亮靠一点。
	return pow(causticsFinal * OMNI_WATER_CAUSTICS_BRIGHTNESS, OMNI_WATER_CAUSTICS_POWER); // 按 Eclipse `settings.glsl:999-1000` 的亮度倍率与对比指数重整，默认全一、画面不变。
}
#endif // 文件守卫结束。
