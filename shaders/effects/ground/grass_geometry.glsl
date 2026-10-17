/*
程序化草几何体：在地形几何阶段，对草方块朝上的面长出会随风摆动的立体草丛。
来源：Eclipse 的着色器草地（`SHADER_GRASS`），按本项目几何阶段（没有细分着色器）精简。
职责：只提供 `omniGrassGeometry`，用顶点阶段传来的方块编号、方块中心与朝上标记生成草叶并发出顶点。
调用位置：`rendering/terrain.glsl` 的地形几何阶段在顶点转发之后调用一次；关闭选项或不在主世界时整段不编译。
可复制示例：`omniGrassGeometry();`  只在 `#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD` 内调用
调用前提：由 `rendering/terrain.glsl` 引入，且已在同一几何阶段声明 `in` 数组 `v_color`、`v_texCoord`、`v_viewPos`、
  `v_blockID`、`v_grassUp`、`v_blockCenter`、`v_blockLight`、`v_chunkFade`，`out` 量 `color`、`texCoord`、`viewPos`、
  `blockLight`、`materialIDs`、`chunkFade`、`blockID`，以及 `colortex9`、`gbufferProjection`、`gbufferModelView`。
关键设计原因与取舍：草叶按离相机距离分级段数，避免顶点数超标；隔壁方块靠上一帧九号画面查询，见 `effects/ground/grass.glsl`。
*/
#ifndef OMNI_GRASS_GEOMETRY_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_GRASS_GEOMETRY_INCLUDED // 置上标记，后续再次引用直接跳过。
#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD // 关闭程序化草或不在主世界时整段不编译。

// 生成草丛：对草方块顶面按距离分级段数，叠上风与随机方向，然后逐顶点发出。
void omniGrassGeometry(){
		vec3 grassCenter = (v_viewPos[0] + v_viewPos[1] + v_viewPos[2]) / 3.0; // 面中心，视空间。
		float grassDist = length(grassCenter); // 到相机的距离，用来分级密度与高度。
		if (v_blockID[0] == OMNI_GRASS_BLOCK_ID && v_grassUp[0] > 0.5 && grassDist < OMNI_GRASS_RANGE){ // 草方块顶面且在范围内才长草。
			vec3 viewUp = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0); // 视空间里的世界竖直方向。
			vec3 viewEast = mat3(gbufferModelView) * vec3(1.0, 0.0, 0.0); // 视空间里的世界东方向，给隔壁查询用。
			vec3 viewSouth = mat3(gbufferModelView) * vec3(0.0, 0.0, 1.0); // 视空间里的世界南方向。

			// 按距离选段数：近处多几段，远处只留一片大叶，顶点数不超标。
			#if OMNI_GRASS_QUALITY == 2
				int triangle_count = 7; float heightMult = 1.1; // 高密度起始值。
				if (grassDist > 2.5) { triangle_count = 5; heightMult = 1.5; } // 稍远处减一段并加高。
				if (grassDist > 5.5) { triangle_count = 3; heightMult = 2.25; } // 更远再减并加高。
				if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
			#elif OMNI_GRASS_QUALITY == 1
				int triangle_count = 5; float heightMult = 1.5; // 中密度起始值。
				if (grassDist > 7.5) { triangle_count = 3; heightMult = 2.25; } // 稍远处减段加高。
				if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
			#else
				int triangle_count = 3; float heightMult = 2.25; // 低密度起始值。
				if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
			#endif

			// 隔壁方块：读九号画面上一帧记下的编号，判断四个水平邻居是不是草方块。
			// 为什么按邻居的屏幕像素读：世界坐标只有投影到屏幕才有对应的记录。
			float neighborE = omniGrassBlockAt(colortex9, grassCenter + viewEast, gbufferProjection, screenSize); // 东邻居。
			float neighborW = omniGrassBlockAt(colortex9, grassCenter - viewEast, gbufferProjection, screenSize); // 西邻居。
			float neighborS = omniGrassBlockAt(colortex9, grassCenter + viewSouth, gbufferProjection, screenSize); // 南邻居。
			float neighborN = omniGrassBlockAt(colortex9, grassCenter - viewSouth, gbufferProjection, screenSize); // 北邻居。
			// 编号为零表示这一像素没有记录（新加载、被遮挡或第一帧），当作草处理，避免整片草被压低。
			float openE = (neighborE < 0.5 || abs(neighborE - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 东边是否开口。
			float openW = (neighborW < 0.5 || abs(neighborW - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 西边是否开口。
			float openS = (neighborS < 0.5 || abs(neighborS - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 南边是否开口。
			float openN = (neighborN < 0.5 || abs(neighborN - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 北边是否开口。
			float openAvg = (openE + openW + openS + openN) * 0.25; // 四周平均开口程度。
			heightMult *= mix(0.65, 1.0, openAvg) * OMNI_GRASS_HEIGHT; // 旁边不是草就让草矮一点，避免越过台阶。

			// 草叶横向宽度方向：取竖直方向与视线方向的叉乘；正对竖直方向时退回东方向，避免除零。
			vec3 sideRaw = cross(viewUp, normalize(grassCenter)); // 横向宽度方向的原始方向。
			if (length(sideRaw) < 1e-4) sideRaw = viewEast; // 视线与竖直方向平行时换一个方向。
			vec3 bladeSide = normalize(sideRaw) * OMNI_GRASS_BASE_THICKNESS; // 收放到草叶宽度。

			vec2 seed = v_blockCenter[0].xz; // 方块中心的相机相对水平坐标当随机种子，同一方块每次结果一致。
			vec2 randomDir = 2.0 * (texture(noisetex, 0.75 * seed).xy + texture(noisetex, 0.35 * seed.yx).xy) - 1.0; // 两组噪声拼出稳定随机方向。
			vec2 windWorld = omniGrassWindOffset(v_blockCenter[0] + cameraPosition); // 风在方块中心处的世界位移。
			vec3 windView = mat3(gbufferModelView) * vec3(windWorld.x, 0.0, windWorld.y); // 风换成视空间。

			for (int j = 0; j < triangle_count; j++){ // 逐段拼出一片草叶。
				for (int i = 0; i < 3; i++){ // 每段三个顶点。
					vec3 offset = omniGrassBladeVertex(viewUp, bladeSide, heightMult, j, triangle_count, i); // 该角相对底部的偏移。
					float height = clamp(dot(offset, viewUp) / max(heightMult, 1e-4) * 0.5, 0.0, 1.0); // 沿竖直的高度比例。
					vec3 bladePos = grassCenter + offset; // 草叶顶点位置。
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
					blockID = v_blockID[i]; // 编号沿用源顶点，片元写九号画面时仍是草方块。
					EmitVertex(); // 发出草叶顶点。
				}
				EndPrimitive(); // 一段草叶结束。
			}
		}
}
#endif // 仅在开启程序化草的主世界编译。
#endif // OMNI_GRASS_GEOMETRY_INCLUDED 结束。
