/*
效果文件 `effects/shared/skyview.glsl`：天空盒投影、反射月亮圆盘，以及天空贴图与星空类型的共用选项。
调用位置：天空页写天空盒与日月；反射在天空兜底时投影方向并画更大的月亮；水面折射回退天空盒时也要同一套投影。
可复制示例：
    `vec2 skyUv = ProjectSky(worldShadowVector, tileSize);`
    `float moon = RenderMoonDiscReflection(worldDir, worldMoonVector);`
设计原因与取舍：天空盒贴图排成三乘二张面，投影与反投影必须同时改；反射与水面折射共用同一份投影，
    如果在各自页面各写一份，贴图布局一变就会四处错位。把投影、反射月盘与贴图选项放在共享层，
    天空页仍负责真正的天空绘制，反射只拿投影和月盘这两个可复用部件。
    贴图分辨率、月亮贴图、天空盒贴图与星空类型都由这一份选项控制，默认值不变。
*/
#ifndef OMNI_SHARED_SKYVIEW_INCLUDED
#define OMNI_SHARED_SKYVIEW_INCLUDED
// @effect {"label":{"zh_cn":"天空贴图与星空","en_us":"Sky textures & stars"}}
// @option {"label":{"zh_cn":"月亮纹理平滑","en_us":"Moon Texture Smoothing"},"description":{"zh_cn":"用双线性过滤读月亮贴图，低分辨率资源包会显得更糊。","en_us":"Reads the moon texture with bilinear filtering; low-resolution packs look softer."}}
#define OMNI_BILINEAR_MOON_TEXTURE 0 // [0 1]
// @option {"label":{"zh_cn":"盒纹理平滑","en_us":"Skybox Texture Smoothing"},"description":{"zh_cn":"用双线性过滤读天空盒贴图，低分辨率资源包会显得更糊。","en_us":"Reads the skybox texture with bilinear filtering; low-resolution packs look softer."}}
#define OMNI_BILINEAR_SKYBOX_TEXTURE 0 // [0 1]
// @option {"label":{"zh_cn":"月亮纹理","en_us":"Moon Texture"},"description":{"zh_cn":"用资源包的月亮贴图代替内置圆盘。","en_us":"Uses the resource pack moon texture instead of the built-in disc."}}
#define OMNI_MOON_TEXTURE
// @option {"label":{"zh_cn":"盒纹理","en_us":"Skybox Texture"},"description":{"zh_cn":"用资源包的天空盒贴图叠在天空上。","en_us":"Overlays the resource pack skybox texture on the sky."}}
#define OMNI_SKYBOX_TEXTURE 0 // [0 1]
// @option {"label":{"zh_cn":"反射天空盒分辨率","en_us":"Skybox Resolution"},"description":{"zh_cn":"反射里天空贴图的边长，越高越清晰也越费性能。","en_us":"Side length of the reflected sky image; higher is sharper and costlier."},"values":{"32.0":{"zh_cn":"极低","en_us":"Lowest"},"64.0":{"zh_cn":"低","en_us":"Low"},"128.0":{"zh_cn":"中","en_us":"Medium"},"256.0":{"zh_cn":"高","en_us":"High"},"512.0":{"zh_cn":"极高","en_us":"Very high"}}}
#define OMNI_SKY_IMAGE_RESOLUTION 64.0 // [32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0]
// @option {"label":{"zh_cn":"纹理亮度","en_us":"Texture Brightness"},"description":{"zh_cn":"原版星星、月亮贴图和天空盒的亮度倍率。","en_us":"Brightness multiplier for vanilla stars, the moon texture and the skybox."},"slider":true}
#define OMNI_SKY_TEXTURE_BRIGHTNESS 1.0 // [0.0 0.05 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"星星类型","en_us":"Star Type"},"description":{"zh_cn":"关为没有星星，点状为按方向生成的星点，原版为资源包星空贴图。","en_us":"Off has no stars, Dots draws procedural points, Vanilla uses the pack sky texture."},"values":{"0":{"zh_cn":"关","en_us":"Off"},"1":{"zh_cn":"点状","en_us":"Dots"},"2":{"zh_cn":"原版","en_us":"Vanilla"}}}
#define OMNI_STAR_TYPE 1 // [0 1 2]
// @option {"label":{"zh_cn":"星星数量","en_us":"Stars Amount"},"description":{"zh_cn":"点状星空的星点疏密倍率，默认一倍与现在一致；只在星星类型为点状时生效。","en_us":"Density multiplier for the Dots star field; default 1 matches the current look; only used with the Dots star type."},"slider":true}
#define OMNI_STARS_AMOUNT 1.0 // [0.5 0.75 1.0 1.25 1.5 1.75 2.0]
// @option {"label":{"zh_cn":"星星亮度","en_us":"Stars Brightness"},"description":{"zh_cn":"点状星空的星点整体亮度倍率，默认一倍与现在一致；只在星星类型为点状时生效。","en_us":"Overall brightness multiplier for the Dots star field; default 1 matches the current look; only used with the Dots star type."},"slider":true}
#define OMNI_STARS_BRIGHTNESS 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"彩色星点","en_us":"Colored Stars"},"description":{"zh_cn":"改用带星温的彩色星场（Eclipse 的 `starbox`）；关闭时是 Eclipse 默认的白色星点，只在星星类型为点状时生效。","en_us":"Uses the star-temperature colored field (Eclipse `starbox`); off keeps Eclipse's default white stars; only used with the Dots star type."}}
#define OMNI_STARS_COLORED 0 // [0 1]
// 天空盒方向与纹素换算放在通用库，这里只传单面边长。
#include "/omni-gfx/atmosphere/atmosphere.glsl"
// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `ProjectSky` 互为逆。
vec3 UnprojectSky(vec2 texel, float tileSize){
	return ogxSkyUnproject(texel, tileSize); // 转发到通用库。
}
// 把一个世界方向投到天空盒三维贴图上，与 `UnprojectSky` 互为逆；原程序两处各写一份，按合同只保留这里一份。
// 调用前提：`screenSize` 与 `pixelSize` 已由绘制主体声明。
vec2 ProjectSky(vec3 dir, float tileSize){
	vec2 texel = ogxSkyProject(dir, tileSize); // 先算三乘二贴图内的纹素坐标。
	texel.y += ceil(screenSize.y * 0.5 + 1.0); // 天空盒贴图放在上半屏，纵坐标抬到上半屏起点。
	return texel * pixelSize; // 纹素坐标换成零到一的贴图坐标。
}
// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float RenderMoonDiscReflection(vec3 worldDir, vec3 moonDir){
	return ogxMoonDiscReflection(worldDir, moonDir); // 转发到通用库。
}
// 双线性取天空贴图：在图块内按四角纹素插值，比普通双线性更可控。
vec4 BilinearSkyTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
	coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
	vec2 p = floor(coord); // 整数纹素。
	vec2 f = coord - p; // 小数偏移。
	ivec2 texelX = ivec2(p); // 左下角纹素。
	ivec2 texelW = texelX + 1; // 右上角纹素。
	return mix(mix(texelFetch(texSampler, texelX, 0), texelFetch(texSampler, ivec2(texelW.x, texelX.y), 0), f.x), // 先横向插值。
			   mix(texelFetch(texSampler, ivec2(texelX.x, texelW.y), 0), texelFetch(texSampler, texelW, 0), f.x), // 再横向插值。
			   f.y); // 最后纵向插值。
}
// 天空盒版双线性：每个图块边界内插值，避免跨图块取到相邻面。
vec4 BilinearSkyboxTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
	ivec2 grid = ivec2(floor(coord * vec2(3.0, 2.0))); // 天空盒是三乘二的图块排布。
	int gridSize = int(floor(texSize.y * 0.5)); // 每个图块的边长。
	grid *= gridSize; // 换成像素坐标。
	ivec4 border = ivec4(grid, grid + gridSize - 1); // 该图块的四条边界。
	coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
	vec2 p = floor(coord); // 整数纹素。
	vec2 f = coord - p; // 小数偏移。
	ivec2 texelX = clamp(ivec2(p), border.xy, border.zw); // 左下角夹在图块内。
	ivec2 texelW = clamp(texelX + 1, border.xy, border.zw); // 右上角同样夹住。
	return mix(mix(texelFetch(texSampler, texelX, 0), texelFetch(texSampler, ivec2(texelW.x, texelX.y), 0), f.x), // 横向插值。
			   mix(texelFetch(texSampler, ivec2(texelX.x, texelW.y), 0), texelFetch(texSampler, texelW, 0), f.x), // 横向插值。
			   f.y); // 纵向插值。
}
// 星场纯计算放在通用库，这里只传亮度、密度与星色。

// 星场总入口：按是否开启彩色星点选白色稳定星场或彩色星盒，再缩放成本项目亮度口径。
// 返回最终星点颜色；太阳方向只用于把星场对齐天球。
vec3 CalculateStars(vec3 worldDir, vec3 sunVector){
	worldDir = ogxAlignToSunAxis(worldDir, sunVector); // 按罗德里格公式把星场对齐到太阳方向。

	#if OMNI_STARS_COLORED
		const float starScale = 0.05 / 75.0; // 彩色路径在 Eclipse 里带七十五倍系数，除回去，使两条路径最亮星一致。
		vec3 starColor; // 星场回填的星色。
		return starScale * ogxStarsColored(worldDir, OMNI_STARS_BRIGHTNESS, OMNI_STARS_AMOUNT, starColor) * starColor; // 亮度乘星色。
	#else
		const float starScale = 0.05; // 与旧 `CalculateStars` 最亮星零点零五对齐，保持夜间曝光不变。
		return vec3(starScale * ogxStarsStable(worldDir, OMNI_STARS_BRIGHTNESS, OMNI_STARS_AMOUNT)); // 白色路径没有星温，转成三分量。
	#endif
}
// 参考签名兼容层：Eclipse 的 `stars` 返回亮度并回填星色，亮度口径取本项目的选项。
float stars(vec3 viewPos, out vec3 starColor){
	starColor = vec3(1.0);
	float field = max(1.0 - ogxStarStableField(viewPos * 300.0, 0.99), 0.0);
	return OMNI_STARS_BRIGHTNESS * exp(field * -20.0 * (1.0 / OMNI_STARS_AMOUNT));
}
#endif // OMNI_SHARED_SKYVIEW_INCLUDED
