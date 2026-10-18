/*
视差：在地表材质的高度图上沿视线找可见交点，给出偏移后的采样像素，并可算视差自阴影与法线。
来源：照 iterationT `Lib/IndividualFounctions/Parallax.glsl` 一比一移植（原 `effects/ground/material.glsl` 的视差段）。
调用位置：`effects/ground/material.glsl` 在文件末尾显式引入本文件；任何引入材质文件的图形阶段都会带上它，
  但整段只在地形、实体、方块实体、手、蜘蛛眼这些几何片元阶段编译，其它阶段（合成、后处理等）不参与。
可复制示例：
  `ivec2 texel = ParallaxOcclusionMapping(texCoord, tbn, shadowVector, duv1, duv2, normalTex, parallaxShadow);`
设计原因与取舍：
  视差只服务地表材质，所以从材质文件里拆出来，让搜 `parallax` 能直接找到算法主体。
  选项（`OMNI_PARALLAX_MODE`、`OMNI_PARALLAX_DEPTH` 等）仍留在 `effects/ground/material.glsl`：
  合成阶段（`composite.glsl`）通过引入材质文件读 `OMNI_PARALLAX_MODE` 决定是否应用视差自阴影，选项必须在那个文件可见。
调用前提（iterationT 原样保留）：调用方必须已声明图集采样器 `tex`、`normals`、`gaux4`（方块图集）与视空间位置 `viewPos`，
  地形还要 `flat in` 的 `textureResolution` 与 `atlasSize`。
*/
#ifndef OMNI_PARALLAX_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_PARALLAX_INCLUDED // 置上标记。
// 视差用到共用数学（解码法线）与蓝噪声，显式引入而不依赖调用顺序。
#include "/common/math.glsl"
// --- 视差：沿视线在高度图里找可见交点，并与视差自阴影配合 ---
// 视差只在几何片元编译：它需要 `dFdx`、图集采样器 `tex`/`normals`/`gaux4` 与视空间位置 `viewPos`，
// 合成阶段没有这些全局量；原程序靠“只有几何片元引入 `Parallax.glsl`”达到同样限制，这里显式写出阶段条件。
#if defined OMNI_FRAGMENT && (defined OMNI_TERRAIN_PASS || defined OMNI_ENTITIES_PASS || defined OMNI_BLOCK_PASS || defined OMNI_HAND_PASS || defined OMNI_SPIDEREYES_PASS)
#if OMNI_PARALLAX_MODE > 1 // 平滑模式：双线性高度采样加二分细化。
// 视差阴影用到时间蓝噪声。
#include "/common/noise.glsl"
// 双线性采样式高度：在图块内跨格子读四角高度并插值，越界处用一层薄壳把空隙补平。
// 参数 `tilesBaseTexel` 是图块左上角在图集里的像素坐标，`iTextureResolution` 是图块边长的按位掩码。
// 参数 `isBlock` 表示是否按方块图集回绕：地形阶段恒为真，实体阶段由调用方判断。
float BilinearHeightSample(vec2 coord, ivec2 tilesBaseTexel, float textureResolution, int iTextureResolution, bool isBlock){
	ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
	ivec2 texelW = texelX + 1; // 右上角像素。
	vec2 f = coord - vec2(texelX); // 到左下角的小数偏移。
	if (isBlock){ // 方块图集（地形恒为真，实体用到方块图集时）按图块回绕。
		texelX = tilesBaseTexel + (texelX & iTextureResolution); // 左下角回绕到本图块内。
		texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角同理。
	}
	vec4 sh = vec4(texelFetch(normals, texelX, 0).a, // 左下角高度。
				   texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a, // 右下角高度。
				   texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a, // 左上角高度。
				   texelFetch(normals, texelW, 0).a); // 右上角高度。
	sh += saturate(1.0 - sh * 1e20); // 高度为零表示没有视差数据，补成完整高度，避免出现空洞。
	return mix(mix(sh.x, sh.y, f.x), // 先沿横轴插值两对。
			   mix(sh.z, sh.w, f.x), // 再沿横轴插值另外两对。
			   f.y); // 最后沿纵轴插值得到高度。
}
// 用高度差直接生成法线：平滑模式可以只用高度场求梯度，得到与视差一致的法线。
// 参数 `isBlock` 表示是否按方块图集回绕：地形阶段恒为真，实体阶段由调用方判断。
vec3 HeightBasedNormal(vec2 coord, ivec2 tilesBaseTexel, float textureResolution, int iTextureResolution, bool isBlock){
	coord -= 0.5; // 把坐标移到像素中心。
	ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
	ivec2 texelW = texelX + 1; // 右上角像素。
	vec2 f = coord - vec2(texelX); // 小数偏移。
	if (isBlock){ // 方块图集（地形恒为真，实体用到方块图集时）按图块回绕。
		texelX = tilesBaseTexel + (texelX & iTextureResolution); // 左下角回绕。
		texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角回绕。
	}
	vec4 sh = vec4(texelFetch(normals, texelX, 0).a, // 四角高度，含义同上一函数。
				   texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a,
				   texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a,
				   texelFetch(normals, texelW, 0).a);
	#if OMNI_PARALLAX_MODE == 2 // 平滑模式：直接由四角高度差得到梯度。
		sh.w = sh.y + sh.z - sh.x - sh.w; // 把四角合成一个中心差分量。
		return vec3(sh.w * f.yx + (sh.x - sh.yz), (8.0 / OMNI_PARALLAX_DEPTH) / textureResolution); // 梯度乘深度再归一化，深度越大法线越陡。
	#else
		const float eps = 0.01; // 靠近像素边缘时梯度会突变，用一个小阈值把它压平。
		f -= 0.5; // 偏移改到像素中心附近。
		float dX = mix(sh.x - sh.y, sh.z - sh.w, saturate(f.y * 1e20)) * saturate((eps - abs(f.x)) * 1e20); // 横向梯度，越靠边越弱。
		float dY = mix(sh.x - sh.z, sh.y - sh.w, saturate(f.x * 1e20)) * saturate((eps - abs(f.y)) * 1e20); // 纵向梯度同理。
		return vec3(dX, dY, step(abs(dX) + abs(dY), 0.0)); // 没有梯度的地方朝外。
	#endif
}
// 平滑视差：从当前坐标沿视线步进求交，再做若干次二分细化，最后可选算阴影与法线。
// 参数 `tbnMat` 是切线基，`shadowVector` 是视空间阳光方向，`duv1`、`duv2` 是纹理坐标的屏幕导数。
ivec2 ParallaxOcclusionMapping(vec2 coord, mat3 tbnMat, vec3 shadowVector, vec2 duv1, vec2 duv2, inout vec3 normalTex, inout float parallaxShadow){
	bool isBlock = true; // 是否按方块图集回绕；地形阶段恒为真。
	#ifndef OMNI_TERRAIN_PASS
		const float textureResolution = OMNI_ENTITIES_TEXTURE_RESOLUTION; // 实体用整数分辨率。
		ivec2 atlasSize = textureSize(tex, 0); // 实体图集大小由采样器读出。
		isBlock = textureSize(gaux4, 0) == atlasSize; // 实体阶段：图集大小与方块图集一致才回绕。
	#endif
	vec2 atlasTiles = vec2(atlasSize) / textureResolution; // 图集里横纵各有多少个图块。
	#ifdef OMNI_PARALLAX_FADE // 需要淡出时先算这一处的淡出因子。
		vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
		float fade = saturate(pow(max(duvMax.x, duvMax.y), -0.1) * (1.0 / 1.4)); // 像素越小越淡出，避免远处闪烁。
	#endif
	vec2 tilesBaseCoord = floor(coord * atlasTiles); // 当前坐标落在哪个图块。
	ivec2 tilesBaseTexel = ivec2(tilesBaseCoord * textureResolution); // 该图块左上角的像素坐标。
	int iTextureResolution = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
	vec3 parallaxTexelCoord = vec3(coord * atlasSize, 1.0); // 换成图集像素坐标并把深度放到一。
	float sampleHeight = BilinearHeightSample(parallaxTexelCoord.xy - 0.5, tilesBaseTexel, textureResolution, iTextureResolution, isBlock); // 先读起始高度。
	if (sampleHeight > 0.0 && sampleHeight < 1.0){ // 只有处在表面内部的像素才需要偏移。
		parallaxTexelCoord.xy -= 0.5; // 坐标移到像素中心。
		vec3 viewVector = normalize(viewPos) * tbnMat; // 视线方向转到切线空间。
		viewVector /= -viewVector.z; // 归一化到单位深度步长。
		vec3 stepDir = viewVector / OMNI_PARALLAX_QUALITY; // 每一步的方向。
		stepDir.xy *= textureResolution * OMNI_PARALLAX_DEPTH * 0.25; // 横向步长按图块尺寸与深度缩放。
		float stepLength = 2.0 / OMNI_PARALLAX_QUALITY; // 逐步加深的初始步长。
		for (int i = 0; i < OMNI_PARALLAX_QUALITY; i++, stepLength += 2.0 / OMNI_PARALLAX_QUALITY){ // 线性步进找交点。
			parallaxTexelCoord += stepDir * stepLength; // 前进一小步。
			sampleHeight = BilinearHeightSample(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock); // 读这一步的高度。
			if (sampleHeight > parallaxTexelCoord.z) break; // 表面高度超过步进深度就找到了交点。
		}
		for (int i = 0; i < OMNI_PARALLAX_MAX_REFINEMENTS; i++){ // 二分细化交点。
			if (sampleHeight > parallaxTexelCoord.z){ // 越过交点就回退半步。
				parallaxTexelCoord -= stepDir * stepLength; // 回退。
				stepLength *= 0.5; // 步长减半。
			}
			parallaxTexelCoord += stepDir * stepLength; // 再前进一个更小的步。
			sampleHeight = BilinearHeightSample(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock); // 读高度。
		}
		if (sampleHeight <= parallaxTexelCoord.z) parallaxTexelCoord += stepDir * stepLength * 2.0; // 最后仍未越界就多走两步，避免停在表面下。
		#if OMNI_PARALLAX_SHADOW // 需要视差自阴影时。
			if (parallaxShadow > 0.0){ // 只有原先允许受光的像素才算阴影。
				shadowVector = shadowVector * tbnMat; // 阳光方向转到切线空间。
				shadowVector /= shadowVector.z * 0.9 + 0.1; // 归一化到单位深度步长，避免水平方向过大。
				vec3 shadowTexelCoord = parallaxTexelCoord; // 从交点出发。
				vec3 stepSize = shadowVector / (OMNI_PARALLAX_SHADOW_QUALITY); // 阴影步进方向。
				stepSize.xy *= textureResolution * OMNI_PARALLAX_DEPTH * 0.25; // 横向步长按图块与深度缩放。
				#ifdef OMNI_TAA // 开时间抗锯齿时用蓝噪声抖动起点。
					shadowTexelCoord += stepSize * BlueNoiseTemporal().x; // 逐像素抖动，让噪点被时间平均。
				#else
					shadowTexelCoord += stepSize; // 不开时只多走一步。
				#endif
				for (int i = 0; i < OMNI_PARALLAX_SHADOW_QUALITY; i++, shadowTexelCoord += stepSize){ // 沿光方向步进找遮挡。
					if (shadowTexelCoord.z > 1.0) break; // 超出表面顶部就不再遮挡。
					sampleHeight = BilinearHeightSample(shadowTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock); // 读遮挡候选的高度。
					float diff = shadowTexelCoord.z - sampleHeight; // 光线高度减去表面高度，负得越多遮挡越强。
					parallaxShadow *= saturate(diff * 40.0 + 1.0); // 逐步累积遮蔽。
					if (parallaxShadow < 0.003) break; // 已经足够黑就提前结束。
				}
			}
			#ifdef OMNI_PARALLAX_FADE
				parallaxShadow = mix(1.0, parallaxShadow, fade); // 远处淡出阴影，避免闪烁。
			#endif
		#endif
		parallaxTexelCoord.xy += 0.5; // 坐标移回像素角。
		#if OMNI_PARALLAX_BASED_NORMAL == 2 // 全部用视差生成法线时。
			normalTex = HeightBasedNormal(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution, isBlock); // 由高度场求法线。
		#endif
		parallaxTexelCoord.xy = (fract(parallaxTexelCoord.xy / textureResolution) + tilesBaseCoord) * textureResolution; // 把偏移后的坐标折回原本的图块。
	}
	ivec2 parallaxTexel = ivec2(parallaxTexelCoord.xy); // 最终要采样到的像素。
	#if OMNI_PARALLAX_BASED_NORMAL < 2 // 不是全部用视差法线时，照常从法线贴图取。
		normalTex = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 解出切线空间法线。
	#else
		#ifdef OMNI_PARALLAX_FADE
			normalTex = mix(vec3(0.0, 0.0, 1.0), normalTex, fade); // 远处淡出到朝外法线。
		#endif
	#endif
	return parallaxTexel; // 交回被遮挡后的采样像素。
}
#elif OMNI_PARALLAX_MODE == 1 // 锐利模式：逐像素穿越图块，保持像素外观。
// 命中表面后的法线处理：三种「由视差生成法线」取值各不同，集中在本函数里，
// 免得预处理指令把外层 `if/else` 的收口切成两半（原写法把 `}else{` 写在 `#if` 分支内）。
// 参数 `parallaxTexel` 是命中的像素，`hitNormal` 是步进中估计出的法线，`fade` 是远处淡出因子（未开淡出时不会被读）。
// 返回处理后的法线；与当前模式无关时原样返回。
vec3 ParallaxHitNormal(ivec2 parallaxTexel, vec3 hitNormal, float fade){
	#if OMNI_PARALLAX_BASED_NORMAL == 1 // 仅侧面：只有步进里命中侧面时才用视差法线。
		#ifdef OMNI_PARALLAX_FADE
			hitNormal = mix(DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb), hitNormal, fade * (1.0 - hitNormal.z)); // 远处淡出到贴图法线。
		#else
			if (hitNormal.z == 1.0) hitNormal = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 没命中侧面时用贴图法线。
		#endif
	#elif OMNI_PARALLAX_BASED_NORMAL == 2 && defined OMNI_PARALLAX_FADE // 全部用视差法线且需淡出时。
		hitNormal = mix(vec3(0.0, 0.0, 1.0), hitNormal, fade); // 远处淡出到朝外法线。
	#endif
	return hitNormal; // 交回处理后的法线。
}
// 锐利视差：沿视线逐像素穿过高度图，命中后可选算自阴影与法线。
ivec2 ParallaxOcclusionMapping(vec2 coord, mat3 tbnMat, vec3 shadowVector, vec2 duv1, vec2 duv2, inout vec3 hitNormal, inout float parallaxShadow){
	#ifndef OMNI_TERRAIN_PASS
		const float textureResolution = OMNI_ENTITIES_TEXTURE_RESOLUTION; // 实体用整数分辨率。
		ivec2 atlasSize = textureSize(tex, 0); // 实体图集大小。
		bool isBlock = textureSize(gaux4, 0) == atlasSize; // 是否方块图集。
	#endif
	vec2 atlasTiles = vec2(atlasSize) / textureResolution; // 图集里横纵各有多少图块。
	vec2 pixelCoord = coord * vec2(atlasSize); // 当前坐标换算成图集像素。
	ivec2 parallaxTexel = ivec2(floor(pixelCoord)); // 起始像素。
	int iTextureResolution = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
	#ifdef OMNI_PARALLAX_FADE
		vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
		float fade = saturate(pow(max(duvMax.x, duvMax.y), -0.4) * 0.2); // 像素越小越淡出。
	#else
		float fade = 1.0; // 没开淡出时给占位值，法线函数在该配置下不会读它。
	#endif
	float sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 起始高度。
	sampleHeight += saturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
	bool exit = false; // 是否命中了表面。
	if (sampleHeight > 0.0 && sampleHeight < 1.0){ // 只有处在表面内部才穿越。
		ivec2 tilesPixelBase = ivec2(floor(coord * atlasTiles) * textureResolution); // 当前图块左上角的像素。
		vec3 viewVector = normalize(viewPos) * tbnMat; // 视线方向转到切线空间。
		vec3 stepDir = normalize(vec3(viewVector.xy * OMNI_PARALLAX_DEPTH * textureResolution * 0.25, -viewVector.z)); // 每像素前进方向，横向按深度缩放。
		vec2 ardir = abs(1.0 / stepDir.xy); // 每走一个像素在横纵方向各需要多远。
		ivec2 sdir = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 横纵方向的符号，用位运算取正负一。
		vec2 totalStep = (vec2(sdir) * (0.5 - (pixelCoord - vec2(parallaxTexel))) + 0.5) * ardir; // 到下一个像素边界的距离。
		float stepLength = 0.0; // 这一步走过的深度。
		float stepHeight = 1.0; // 这一步光线所在的高度。
		float prevStepHeight = 1.0; // 上一步高度，用于判断交点落在哪一列。
		ivec2 stepNext = ivec2(0); // 这一步往哪个方向跨像素。
		for (int i = 0; i < OMNI_PARALLAX_QUALITY; i++){ // 逐像素前进。
			stepLength = min(totalStep.x, totalStep.y); // 先碰到哪一侧边界就按哪一侧走。
			stepHeight = 1.0 - stepLength * stepDir.z; // 这一步光线到达的高度。
			if (sampleHeight > stepHeight){ // 表面高过光线，说明这一段遮挡了像素。
				if (sampleHeight > prevStepHeight){ // 交点落在上一步与这一步之间时用上一步的法线。
					hitNormal = vec3(-stepNext * sdir, 0.0); // 由跨步方向估计侧面法线。
					sampleHeight = prevStepHeight; // 高度取上一步，便于后续阴影。
				}
				exit = true; // 标记命中。
				break; // 结束步进。
			}
			stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 判断这一步跨的是哪一侧。
			parallaxTexel += stepNext * sdir; // 前进到下一个像素。
			totalStep += vec2(stepNext) * ardir; // 累加边界距离。
			prevStepHeight = stepHeight; // 记下这一步高度。
			#ifndef OMNI_TERRAIN_PASS
				bool wrapTile = isBlock; // 实体只在用到方块图集时回绕到本图块。
			#else
				bool wrapTile = true; // 地形阶段总是回绕到本图块。
			#endif
			if (wrapTile){ // 先用宏决定是否回绕，再走一条完整的 `if`，避免判断括号被预处理指令切开。
				parallaxTexel = tilesPixelBase + (parallaxTexel & iTextureResolution); // 把像素折回本图块。
			}
			sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 读新像素的高度。
			sampleHeight += saturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
		}
		#if OMNI_PARALLAX_SHADOW // 需要自阴影时。
			shadowVector = shadowVector * tbnMat; // 阳光方向转到切线空间。
			float shadow = 1.0; // 阴影透过率从全透开始。
			if (dot(shadowVector, hitNormal) * parallaxShadow > 0.0 && exit){ // 命中的侧面朝向阳光才需要阴影。
				float currHeight = sampleHeight; // 当前高度。
				stepLength = (1.0 - currHeight) / stepDir.z; // 先走到表面顶部。
				vec2 shadowTexelCoord = pixelCoord + stepLength * stepDir.xy; // 到达顶部时的像素坐标。
				ivec2 shadowTexel = ivec2(floor(shadowTexelCoord)); // 取整。
				stepDir = normalize(vec3(shadowVector.xy * OMNI_PARALLAX_DEPTH * textureResolution * 0.25, shadowVector.z)); // 换成沿光方向的前进方向。
				vec2 ardir = abs(1.0 / stepDir.xy); // 每像素的边界距离。
				ivec2 sdir = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 方向符号。
				totalStep = (vec2(sdir) * (0.5 - (shadowTexelCoord - shadowTexel)) + 0.5) * ardir; // 到下一像素边界的距离。
				stepNext = ivec2(0); // 复位跨步方向。
				for (int i = 0; i < OMNI_PARALLAX_SHADOW_QUALITY; i++){ // 沿光方向逐像素找遮挡。
					stepLength = min(totalStep.x, totalStep.y); // 先碰到的边界。
					stepHeight = currHeight + stepLength * stepDir.z; // 这一步的高度。
					stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 跨哪一侧。
					shadowTexel += stepNext * sdir; // 前进到下一个像素。
					totalStep += vec2(stepNext) * ardir; // 累加边界距离。
					#ifndef OMNI_TERRAIN_PASS
						bool wrapTile = isBlock; // 实体只在用到方块图集时回绕。
					#else
						bool wrapTile = true; // 地形阶段总是回绕。
					#endif
					if (wrapTile){ // 先用宏决定是否回绕，再走一条完整的 `if`。
						shadowTexel = tilesPixelBase + (shadowTexel & iTextureResolution); // 折回本图块。
					}
					sampleHeight = texelFetch(normals, shadowTexel, 0).a; // 读高度。
					sampleHeight += saturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
					if (sampleHeight > stepHeight){ // 表面高过光线，说明被遮挡。
						parallaxShadow = 0.0; // 直接判为阴影。
						break; // 结束。
					}
				}
				#ifdef OMNI_PARALLAX_FADE
					parallaxShadow *= mix(1.0, shadow, fade); // 远处淡出阴影。
				#else
					parallaxShadow *= shadow; // 否则原样。
				#endif
			}
		#endif
		hitNormal = ParallaxHitNormal(parallaxTexel, hitNormal, fade); // 命中后按当前模式处理法线。
	}else{
		#if OMNI_PARALLAX_BASED_NORMAL == 1 // 仅侧面模式：没命中侧面就退回贴图法线。
			hitNormal = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 没命中时直接用贴图法线。
		#endif
	}
	#if OMNI_PARALLAX_BASED_NORMAL == 0 // 不用视差法线时一律取贴图法线。
		hitNormal = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 解出切线空间法线。
	#endif
	return parallaxTexel; // 交回最终采样像素。
}
#endif // 平滑与锐利两种视差结束。
#endif // 几何片元视差段结束。
#endif // 文件守卫结束。
