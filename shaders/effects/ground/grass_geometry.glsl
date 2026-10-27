/*
效果文件 `effects/ground/grass_geometry.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/ground/grass_geometry.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_GRASS_GEOMETRY_INCLUDED
#define OMNI_GRASS_GEOMETRY_INCLUDED
/*
程序化草几何体：在地形几何阶段长出会随风摆动的立体草丛。
来源：Eclipse 的着色器草地（`SHADER_GRASS`）；Eclipse 用细分着色器把一个面细分成很多小三角各长一片草，
本项目没有细分阶段，改成按 `OMNI_GRASS_DENSITY` 直接在一个三角形里摊开几片草，见 `effects/ground/grass.glsl`。
职责：只提供 `omniGrassGeometry`，用顶点阶段传来的方块编号、方块中心与朝上标记生成草叶并发出顶点。
调用位置：`rendering/terrain.glsl` 的地形几何阶段在顶点转发之后调用一次；关闭选项或不在主世界时整段不编译。
可复制示例：`omniGrassGeometry();`  只在 `#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD` 内调用
调用前提：由 `rendering/terrain.glsl` 引入，且已在同一几何阶段声明 `in` 数组 `v_color`、`v_texCoord`、`v_viewPos`、
  `v_blockID`、`v_grassUp`、`v_blockCenter`、`v_blockLight`、`v_chunkFade`，`out` 量 `color`、`texCoord`、`viewPos`、
  `blockLight`、`materialIDs`、`chunkFade`、`blockID`，以及 `colortex9`、`gbufferProjection`、`screenSize`。
关键设计原因与取舍：
  草叶按离相机距离分级段数，避免顶点数超标；同一顶面按密度多长几片草来近似 Eclipse 的细分等级。
  两个生长来源，用 `OMNI_REPLACE_SHORT_GRASS == 2`（仅矮草档）切换：
  默认档长在草方块朝上的顶面，草根位置取该三角面的中心（`v_viewPos`）；
  仅矮草档长在原版矮草方块上，草根位置取该方块中心底部（`v_blockCenter`），矮草原版模型已在顶点阶段塌成一点隐藏。
  为什么仅矮草档按矮草方块生长：Eclipse 用体素缓冲查「草方块顶上有没有矮草」，本项目几何阶段没有体素缓冲，
  也没有能记录被隐藏矮草的通道，只能直接从矮草方块自己的三角形生长，属近似。
  邻接检测走九号画面（上一帧内容）：几何阶段拿不到邻接关系，只能按世界坐标投影到屏幕再取记录。
  仅矮草档下同一矮草方块会被几个三角形各生长一次、叠加在同一处，观感相同但会多花几倍顶点，属同一近似。
*/
#if OMNI_SHADER_GRASS && defined OMNI_OVERWORLD // 关闭程序化草或不在主世界时整段不编译。

// 判断一个邻居对草丛高度的作用：旁边是草或矮草就加高，临台阶就压低，其余不动。
// `neighborId` 是九号画面里那一格的方块编号，`neighborPos` 是它的视空间位置，`viewUp` 是世界竖直方向。
// 为什么用正负零三档：Eclipse 把四邻各折成一个约正负四分之一的分量，这里直接取档位再平均，效果等价。
float omniGrassSideSign(float neighborId, vec3 neighborPos, vec3 viewUp){
	if (abs(neighborId - OMNI_GRASS_BLOCK_ID) < 0.5 || abs(neighborId - OMNI_SHORT_GRASS_BLOCK_ID) < 0.5) return 1.0; // 邻居是草方块或矮草，抬高。
	if (neighborId < 0.5) return 0.0; // 没有记录（新加载、被遮挡或第一帧），保守当平，避免整片草被压低。
	#if OMNI_GRASS_DETECT_FALLOFF // 开启底部检测时才向下多查一格。
		float below = omniGrassBlockAt(colortex9, neighborPos - viewUp, gbufferProjection, screenSize); // 邻居正下方一格的编号。
		if (below >= 0.5 && abs(below - OMNI_GRASS_BLOCK_ID) >= 0.5 && abs(below - OMNI_SHORT_GRASS_BLOCK_ID) >= 0.5) return -1.0; // 下方也不是草，说明是台阶，压低。
	#endif
	return 0.0; // 其余情况不加不减。
}

// 生成草丛：先决定草根位置与高度，再叠上风与随机方向，然后逐顶点发出。
void omniGrassGeometry(){
	bool onlyShortGrass = (OMNI_REPLACE_SHORT_GRASS == 2); // 仅矮草档：只长在矮草方块上，草方块顶面不长。
	vec3 viewUp = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0); // 视空间里的世界竖直方向。
	vec3 viewEast = mat3(gbufferModelView) * vec3(1.0, 0.0, 0.0); // 视空间里的世界东方向，给邻接查询与摊开用。
	vec3 viewSouth = mat3(gbufferModelView) * vec3(0.0, 0.0, 1.0); // 视空间里的世界南方向。

	// 挑出该长草的三角形，并给出草根基准点。
	vec3 bladeBaseCenter; // 草根所在处的中心，随后按密度在它周围摊开几片草。
	if (onlyShortGrass){ // 仅矮草档：认矮草方块（编号 12）。
		if (v_blockID[0] != OMNI_SHORT_GRASS_BLOCK_ID) return; // 其它方块一律不长。
		bladeBaseCenter = mat3(gbufferModelView) * v_blockCenter[0] - viewUp * 0.5; // 方块中心底部就是下方方块的顶面。
	} else { // 默认档：认草方块（编号 85）朝上的顶面。
		if (v_blockID[0] != OMNI_GRASS_BLOCK_ID || v_grassUp[0] <= 0.5) return; // 不是草方块顶面就整段不做事。
		bladeBaseCenter = (v_viewPos[0] + v_viewPos[1] + v_viewPos[2]) / 3.0; // 面中心，视空间。
	}
	float grassDist = length(bladeBaseCenter); // 到相机的距离，用来分级段数与范围。
	if (grassDist >= OMNI_GRASS_RANGE) return; // 范围外不生长。

	// 按距离选段数与高度基准：近处多几段，远处只留一片大叶，顶点数不超标。
	#if OMNI_GRASS_QUALITY == 2
		int triangle_count = 7; float heightMult = 1.1; // 高质量起始值。
		if (grassDist > 2.5) { triangle_count = 5; heightMult = 1.5; } // 稍远处减一段并加高。
		if (grassDist > 5.5) { triangle_count = 3; heightMult = 2.25; } // 更远再减并加高。
		if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
	#elif OMNI_GRASS_QUALITY == 1
		int triangle_count = 5; float heightMult = 1.5; // 中等质量起始值。
		if (grassDist > 7.5) { triangle_count = 3; heightMult = 2.25; } // 稍远处减段加高。
		if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
	#else
		int triangle_count = 3; float heightMult = 2.25; // 低质量起始值。
		if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
	#endif

	// 高度定标：照 Eclipse 的 `totalHeightMult`，四邻合起来抬高或压低，再叠两种高度。
	if (onlyShortGrass){ // 仅矮草档：四周都是矮草，直接取“被矮草围住”这一档。
		heightMult *= 0.5 * OMNI_GRASS_SHORT_HEIGHT + OMNI_GRASS_BASE_HEIGHT; // 照 Eclipse 把四项正方向分量都算满。
	} else { // 默认档：查四邻是不是草。
		float idE = omniGrassBlockAt(colortex9, bladeBaseCenter + viewEast, gbufferProjection, screenSize); // 东邻居。
		float idW = omniGrassBlockAt(colortex9, bladeBaseCenter - viewEast, gbufferProjection, screenSize); // 西邻居。
		float idS = omniGrassBlockAt(colortex9, bladeBaseCenter + viewSouth, gbufferProjection, screenSize); // 南邻居。
		float idN = omniGrassBlockAt(colortex9, bladeBaseCenter - viewSouth, gbufferProjection, screenSize); // 北邻居。
		float signE = omniGrassSideSign(idE, bladeBaseCenter + viewEast, viewUp); // 东侧作用档。
		float signW = omniGrassSideSign(idW, bladeBaseCenter - viewEast, viewUp); // 西侧作用档。
		float signS = omniGrassSideSign(idS, bladeBaseCenter + viewSouth, viewUp); // 南侧作用档。
		float signN = omniGrassSideSign(idN, bladeBaseCenter - viewSouth, viewUp); // 北侧作用档。
		#if !OMNI_GRASS_DETECT_INV_FALLOFF // 关掉侧向检测：去掉加高，只保留底部检测的压低。
			signE = min(signE, 0.0); signW = min(signW, 0.0); signS = min(signS, 0.0); signN = min(signN, 0.0); // 正档归零。
		#endif
		float neighborSum = 0.25 * (signE + signW + signS + signN); // 四邻合起来落在负一到一之间。
		float baseHeight = OMNI_GRASS_BASE_HEIGHT; // 缩短名字，下面的公式更好读。
		heightMult *= 0.5 * clamp(neighborSum, -baseHeight * baseHeight, OMNI_GRASS_SHORT_HEIGHT) + baseHeight; // 中间抬高、边缘压低，再叠普通草高度。
	}

	vec2 windWorld = omniGrassWindOffset(v_blockCenter[0] + cameraPosition); // 风在方块中心处的世界位移，同面几片草共用。
	vec3 windView = mat3(gbufferModelView) * vec3(windWorld.x, 0.0, windWorld.y); // 风换成视空间。

	for (int b = 0; b < OMNI_GRASS_BLADES; b++){ // 按密度在同一处摊开几片草。
		vec3 bary = omniGrassBladeBarycentric(b, OMNI_GRASS_BLADES); // 该片的重心权重。
		vec3 bladeBase; // 该片草根部的视空间位置。
		if (onlyShortGrass){ // 仅矮草档没有三角面可插值，用方块底面的三个角把几片草摊在方块内。
			vec3 cornerA = bladeBaseCenter + viewEast * 0.4 + viewSouth * 0.4; // 一个角。
			vec3 cornerB = bladeBaseCenter - viewEast * 0.4 + viewSouth * 0.4; // 相邻的角。
			vec3 cornerC = bladeBaseCenter - viewEast * 0.4 - viewSouth * 0.4; // 再下一个角。
			bladeBase = cornerA * bary.x + cornerB * bary.y + cornerC * bary.z; // 按重心权重落在方块内一点。
		} else {
			bladeBase = v_viewPos[0] * bary.x + v_viewPos[1] * bary.y + v_viewPos[2] * bary.z; // 顶面三角形内的一点。
		}
		// 每片草自己的随机种子：方块中心叠加按序号错开的偏移，同一方块每片不同，跨帧稳定。
		vec2 seed = v_blockCenter[0].xz + float(b) * vec2(0.37, 0.61); // 逐片错开的随机种子。
		vec2 randomDir = 2.0 * (texture(noisetex, 0.75 * seed).xy + texture(noisetex, 0.35 * seed.yx).xy) - 1.0; // 两组噪声拼出稳定随机方向。

		// 草叶横向宽度方向：取竖直方向与视线方向的叉乘；正对竖直方向时退回东方向，避免除零。
		vec3 sideRaw = cross(viewUp, normalize(bladeBase)); // 横向宽度方向的原始方向。
		if (length(sideRaw) < 1e-4) sideRaw = viewEast; // 视线与竖直方向平行时换一个方向。
		vec3 bladeSide = normalize(sideRaw) * OMNI_GRASS_BASE_THICKNESS; // 收放到草叶宽度。
		float bladeHeight = heightMult * mix(0.85, 1.15, randomDir.y * 0.5 + 0.5); // 每片高度略有起伏，草不会一样齐。

		for (int j = 0; j < triangle_count; j++){ // 逐段拼出一片草叶。
			for (int i = 0; i < 3; i++){ // 每段三个顶点。
				vec3 offset = omniGrassBladeVertex(viewUp, bladeSide, bladeHeight, j, triangle_count, i); // 该角相对底部的偏移。
				float height = clamp(dot(offset, viewUp) / max(bladeHeight, 1e-4) * 0.5, 0.0, 1.0); // 沿竖直的高度比例。
				vec3 bladePos = bladeBase + offset; // 草叶顶点位置。
				bladePos += windView * height * height; // 越高越被风吹弯。
				bladePos += normalize(bladeSide) * OMNI_GRASS_RANDOMNESS * randomDir.x * height; // 每片草随机方向的小弯。

				gl_Position = gbufferProjection * vec4(bladePos, 1.0); // 投影到裁剪空间。
				#ifdef OMNI_TAA
					gl_Position.xy += taaJitter * gl_Position.w; // 与顶点阶段一致地加本帧抖动，避免草叶和时间抗锯齿错位。
				#endif

				color = v_color[i]; // 草叶底色沿用源顶点色。
				texCoord = v_texCoord[i]; // 贴图坐标沿用源顶点，草叶显示草方块的贴图。
				viewPos = bladePos; // 视空间位置，片元做切线基与视差要用。
				blockLight = v_blockLight[i]; // 方块光沿用源顶点。
				materialIDs = MATID_GRASS; // 草叶按草处理，湿润与光照走草的路径。
				chunkFade = v_chunkFade[i]; // 新加载区块的草叶同样淡入。
				blockID = OMNI_GRASS_BLOCK_ID; // 草叶一律记成草方块，片元写九号画面时仍按草处理。
				EmitVertex(); // 发出草叶顶点。
			}
			EndPrimitive(); // 一段草叶结束。
		}
	}
}
#endif // 仅在开启程序化草的主世界编译。
#endif // OMNI_GRASS_GEOMETRY_INCLUDED
