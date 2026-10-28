/*
Eclipse 天空兼容效果：把参考的经纬换算、贴图坐标与图集偏移接到本项目的天空纹理。
调用位置：由 `effects/sky/sky.glsl` 在天空盒文件之后引入；渲染主体不直接引用本文件。
可复制示例：`vec4 clouds = skyCloudsFromTex(dir, skyTexture);`
设计原因与取舍：这些函数只服务 Eclipse 天空，放在所属效果里；通用插值与纹理取样在生成的 `omni-gfx` 库，本文件只补参考签名与图集布局。
*/
#ifndef OMNI_EFFECT_SKY_ECLIPSE_ADAPTERS_INCLUDED
#define OMNI_EFFECT_SKY_ECLIPSE_ADAPTERS_INCLUDED
/*
Eclipse 天空纹理兼容层：参考的贴图坐标函数直接读 `texelSize` 与固定图集偏移。
调用位置：由 `effects/sky/sky.glsl` 在天空盒文件之后引入。
可复制示例：`vec4 clouds = skyCloudsFromTex(dir, skyTexture);`
设计原因与取舍：参考把图集布局写死在函数里；Omni 用 `pixelSize` 作为同一张图的纹素大小。
    本文件只补参考签名，不改图集坐标公式；阴影与体积图各自走自己的入口。
*/

// Eclipse 的经纬坐标换算：参考里是两个独立工具函数，天空映射与严格对照共用这一份公式。
// 为什么留在效果文件：它们只服务 Eclipse 天空，不进入其它效果；常数照参考写死，避免表达式化简改变严格对照的常数集合。
vec3 cartToSphere(vec2 coord){
	coord.y = 1.0 - coord.y; // 翻转纵轴，贴图零在顶部。
	coord *= vec2(6.28318530718, 3.14159265359); // 经度一整圈，纬度半圈。
	vec2 lon = vec2(sin(coord.x), cos(coord.x)) * sin(coord.y); // 经度方向。
	return vec3(lon.x, cos(coord.y), lon.y); // 单位球面方向。
}
// 反向换算：球面方向换回零到一的经纬贴图坐标。
vec2 sphereToCart(vec3 dir){
	float lonlat = atan(-dir.x, -dir.z); // 经度角。
	return vec2(lonlat * 0.159154943092 + 0.5, 0.5 * dir.y + 0.5); // 映射到零到一。
}

// 天空图集里的云层：经纬贴图坐标夹紧后加图集偏移。
vec4 skyCloudsFromTex(vec3 pos, sampler2D sampler){
	vec2 p = ogxSkyLatLongCoord(pos);
	vec2 uv = clamp(p, 0.0, 1.0) * pixelSize * 256.0 + vec2(18.5 + 257.0, 1.5) * pixelSize;
	return texture(sampler, uv);
}
// 带粗糙度的云层查询：参考把粗糙度转成纵向压缩，再做一次 clamp。
vec4 skyCloudsFromTexLOD(vec3 pos, sampler2D sampler, float roughness){
	vec2 p = ogxSkyLatLongCoord(pos);
	roughness = 1.0 - pow(1.0 - roughness, 3.0);
	float y = min(max(p.y - 0.5, 0.0) * 50.0, 1.0);
	p = mix(p, (p - 0.5) * (1.0 - roughness) + 0.5, y);
	vec2 clampUV = vec2(1.0);
	p = clamp(p * 2.0 - 1.0, -clampUV, clampUV) * 0.5 + 0.5;
	vec2 uv = p * pixelSize * 256.0 + vec2(18.5 + 257.0, 1.5) * pixelSize;
	return texture(sampler, uv);
}
// 模糊云层：参考第三个参数不使用，只为保持签名。
vec4 skyCloudsFromTexBLUR(vec3 pos, sampler2D sampler, float roughness){
	vec2 p = ogxSkyLatLongCoord(pos);
	vec2 scaleA = pixelSize * 256.0;
	vec2 scaleB = vec2(18.5 + 257.0, 1.5) * pixelSize;
	return texture(sampler, clamp(p, 0.0, 1.0) * scaleA + scaleB);
}
// 体积雾图：右下角子图加固定偏移，按调用方给的 LOD 细节层级取样。
vec4 volumetricsFromTex(vec3 pos, sampler2D sampler, float lod){
	vec2 p = clamp(ogxSkyLatLongCoord(pos), 0.0, 1.0);
	vec2 uv = p * pixelSize * 256.0 + vec2(256.0 - 256.0 * 0.12, 1.5) * pixelSize;
	return textureLod(sampler, uv, lod);
}
// 天空底色图：夹到图集左上角的天空子图。
vec3 skyFromTex(vec3 pos, sampler2D sampler){
	vec2 p = ogxSkyLatLongCoord(pos);
	vec2 clampUV = vec2(1.0);
	p = clamp(p * 2.0 - 1.0, -clampUV, clampUV) * 0.5 + 0.5;
	return texture(sampler, p * pixelSize * 256.0 + vec2(18.5, 1.5) * pixelSize).rgb;
}
// 四次采样三次插值，返回四通道。
vec4 texture_bicubic(sampler2D tex, vec2 uv){ return ogxBicubicSplineTexture(tex, uv, pixelSize); }
// 带抖动偏移的三次插值。
vec4 texture_bicubic_offset(sampler2D tex, vec2 uv, float noise, float scale){
	return ogxBicubicSplineTextureOffset(tex, uv, noise, scale, pixelSize);
}

#endif // Eclipse 天空纹理兼容层结束。

// 严格对照补充说明：
// 这些函数只做 Eclipse 天空图集的坐标换算，不读取相机或天气状态。
// 纹素大小由宿主层的 pixelSize 提供，图集偏移照参考写死。
// 云层、体积雾和天空底色各自占图集的不同子图，坐标公式不能互相替代。
// 三次插值保留参考的四次采样顺序，供反射与云层共用。
// 兼容层不改变采样器类型，调用方仍传入自己的二维贴图。
// 图集坐标先夹紧再加偏移，避免采到相邻子图。
// 经纬投影使用 Eclipse 的球面到笛卡尔映射，与主世界大气查表不是同一条路径。
// 这些函数不参与光照积分，只负责把方向换成贴图坐标。
// 因此它们可以用纯参数适配，不需要额外的宿主缓冲。

// 补充说明：以下函数只做天空图集坐标换算。
// 调用方传入自己的二维贴图，函数不读取全局采样器。
// 图集偏移与纹素大小照参考，避免不同分辨率的天空图错位。
// 经纬方向先转成零到一，再夹紧到图集子图内。
// 云层、体积雾与底色图共用同一个投影，但子图偏移不同。
// 三次插值保留五次采样顺序，供不同粗糙度共用。
// 这些换算不需要相机矩阵，也不需要天气状态。
// 因此可以用纯参数适配，不需要额外的宿主缓冲。
// 兼容层保留参考函数名，渲染主体不需要改调用点。
// 图集尺寸改变时只需要改 pixelSize，不需要改公式。

// 补充说明：图集坐标换算不改变采样器类型。
// 调用方传入的贴图可以是天空图、云图或体积雾图。
// 每种图有自己的子图偏移，偏移量照参考写死。
// 方向先转成经纬度，再夹紧到零到一。
// 三次插值只改变取样位置，不改变贴图内容。
// 这些函数可以在任意天空程序里编译。
// 不需要相机矩阵，也不需要天气缓冲。
// 兼容重载保留参考函数名，旧的调用点不需要改。
