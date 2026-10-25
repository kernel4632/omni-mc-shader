/*
光传播体积计算入口：`setup` 阶段填方块光表，`shadowcomp` 阶段每帧推进一拍彩色光传播。
来源：Eclipse 的 `dimensions/setup.csh`（方块光表分发）与 `dimensions/shadowcomp.csh`（共享内存里的 floodfill），
  按本项目的计算入口约定改写成“一个主体、两个阶段”：
  `rendering/programs.json` 把 `setup` 与 `shadowcomp` 都登记到本文件，靠 `OMNI_LPV_SETUP`、`OMNI_LPV_SHADOWCOMP` 选分支。
调用位置：各维度 `setup.csh`、`shadowcomp.csh` 入口定义 `OMNI_COMPUTE` 与对应阶段宏后引入本文件；入口由构建生成。
可复制示例：入口写 `#define OMNI_COMPUTE 1`、`#define OMNI_LPV_SHADOWCOMP 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/lpv.glsl"`；选项、光表与坐标映射都来自 `effects/lighting/lpv.glsl`。
设计原因与取舍：
  一、`setup` 只在加载时跑一次，把每个方块编号的颜色、光强、透光率与方向掩码写进一张一维光表；
  二、`shadowcomp` 每次阴影之后跑，用共享内存把每个工作组周围一圈的真实体积值读进来，
     再按邻居掩码与染色混合、叠上本格自发光的“一步”传播，结果写回与上一帧相反的一张体积图；
  三、双缓冲靠 `frameCounter` 的奇偶切换，读一张写另一张，下一帧再交换，保证读到完整的上一步结果；
  四、关闭功能或缺自定义图像能力时两个阶段都保持空实现，不写图也不读图。
*/
#ifndef OMNI_LPV_LIB // 防止重复引用造成重复声明。
#define OMNI_LPV_LIB // 标记本文件已经引入。
// 效果选项、光表、坐标映射与体素读写来自效果主体。
#include "/rendering/lighting/lpv.glsl"

// ========================= 阶段一 setup：填方块光表 =========================
#ifdef OMNI_LPV_SETUP // 只有本阶段编译下面的入口。
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in; // 二维工作组，逐个填表项。
const ivec3 workGroups = ivec3(16, 16, 1); // 每轴十六组，覆盖 128×128 个表项，足够放八千一百九十二项。
// 填表主函数：每个线程负责一个方块编号，算出它的光色、光强、透光率与掩码后写进光表。
void main(){
#if OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭或缺能力时不填表。
	int blockId = int(gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * 128u); // 展平成一维编号，每行 128 项。
	if (blockId < 0 || blockId >= int(omniLpvBlockTableSize)) return; // 超出表范围直接返回。
	uvec2 row = omniLpvBlockData(uint(blockId)); // 算出这个编号的光表项。
	imageStore(omniLpvBlocks, blockId, uvec4(row, 0u, 0u)); // 写入光表，后两字留空。
#endif // 关闭分支结束。
}
#endif // setup 阶段结束。

// ========================= 阶段二 shadowcomp：每帧一步传播 =========================
#ifdef OMNI_LPV_SHADOWCOMP // 只有本阶段编译下面的入口。
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in; // 三维工作组，逐个填体积格。
const ivec3 workGroups = ivec3(32, 32, 32); // 每轴三十二组，覆盖边长上限二百五十六格；超出边长的组由 main 里的判断直接退出。

#if OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭或缺能力时 main 保持空实现。

// 共享缓冲比工作组大一圈（十格）：中间八格是本职工作项，外面一圈是邻居，读邻居不用再访存图。
shared vec4 omniLpvShared[10 * 10 * 10]; // 体积值，含前一帧的时间累积。
shared uint omniVoxelShared[10 * 10 * 10]; // 体素编号，本帧刚写完。
const ivec3 omniLpvFlatten = ivec3(1, 10, 100); // 把三维共享下标展平成一维，照 Eclipse `shadowcomp.csh:18`。
const float omniLpvFalloff = 0.96; // 每步传播的衰减，照 Eclipse `LpvBlockSkyFalloff`。

// 三维下标展平成一维共享下标。
int omniLpvSharedIndex(ivec3 pos){ return dot(pos, omniLpvFlatten); }
// 把一个格子的体积值与体素编号读进共享缓冲：体积值加上跨帧格偏移，体素用本帧坐标。
void omniLpvPopulate(ivec3 imgCoordOffset, ivec3 workGroupOffset, uint i){
	int flat = int(i); // 展平下标，共享缓冲共一千格。
	ivec3 grid = ivec3(flat / omniLpvFlatten.x, flat / omniLpvFlatten.y, flat / omniLpvFlatten.z) % 10; // 共享格坐标，零到九。
	ivec3 pos = workGroupOffset + grid; // 该共享格在体积里的坐标，外面一圈会到负一或边长。
	omniLpvShared[flat] = omniLpvReadAt(imgCoordOffset + pos); // 体积值：读上一帧那张图，并补偿体积随玩家移动的整格位移。
	omniVoxelShared[flat] = omniVoxelRead(pos); // 体素编号：本帧阴影阶段刚写入，直接用当前坐标。
}
// 取一个邻居的体积值，按该格的方向掩码决定它能不能把光传过来。
vec4 omniLpvSampleNeighbour(ivec3 pos, int maskIndex){
	int sharedIndex = omniLpvSharedIndex(pos + 1); // 共享坐标要加一圈偏移。
	uint mask = 0xFFFFu; // 默认六个方向都通。
	uint blockId = omniVoxelShared[sharedIndex]; // 该格的方块编号。
	if (blockId > 0u){ // 空气为零，跳过查表。
		uvec2 blockData = omniLpvBlockRow(blockId); // 读光表项。
		mask = (blockData.g >> 24) & 0xFFFFu; // 高字里的方向掩码。
	}
	return omniLpvShared[sharedIndex] * float((mask >> maskIndex) & 1u); // 该方向不可透就把光清零。
}
// 混合六个邻居：每个方向各挡一次，再乘传播衰减，得到本格接收到的光。
vec4 omniLpvMixNeighbours(ivec3 fragCoord, uint mask){
	uvec3 m1 = (uvec3(mask) >> uvec3(0, 2, 4)) & uvec3(1u); // 负方向（西、下、北）。
	uvec3 m2 = (uvec3(mask) >> uvec3(1, 3, 5)) & uvec3(1u); // 正方向（东、上、南）。

	vec4 sX1 = omniLpvSampleNeighbour(fragCoord + ivec3(-1, 0, 0), 1) * float(m1.x); // 西邻居，本格西向掩码。
	vec4 sX2 = omniLpvSampleNeighbour(fragCoord + ivec3( 1, 0, 0), 0) * float(m2.x); // 东邻居，本格东向掩码。
	vec4 sY1 = omniLpvSampleNeighbour(fragCoord + ivec3(0, -1, 0), 3) * float(m1.y); // 下邻居，本格下向掩码。
	vec4 sY2 = omniLpvSampleNeighbour(fragCoord + ivec3(0,  1, 0), 2) * float(m2.y); // 上邻居，本格上向掩码。
	vec4 sZ1 = omniLpvSampleNeighbour(fragCoord + ivec3(0, 0, -1), 5) * float(m1.z); // 北邻居，本格北向掩码。
	vec4 sZ2 = omniLpvSampleNeighbour(fragCoord + ivec3(0, 0,  1), 4) * float(m2.z); // 南邻居，本格南向掩码。

	vec4 avgFalloff = vec4(omniLpvFalloff / 6.0, omniLpvFalloff / 6.0, omniLpvFalloff / 6.0, omniLpvFalloff / 6.0); // 六分之一乘衰减。
	return (sX1 + sX2 + sY1 + sY2 + sZ1 + sZ2) * avgFalloff; // 六个邻居求和后取平均。
}
#endif // 开关与能力条件结束。

// 传播主函数：先把周围十立方读进共享，再一个格子算一次混合加自发光，最后写回本帧那张图。
void main(){
#if OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭或缺能力时保持空实现。
	uvec3 chunkPos = gl_WorkGroupID * gl_WorkGroupSize; // 本工作组的起点格。
	if (any(greaterThanEqual(chunkPos, uvec3(omniLpvSide)))) return; // 超出体积边长的工作组直接退出。

	uint i = uint(gl_LocalInvocationIndex) * 2u; // 每个线程搬两个共享格，512 线程刚好搬满 1000 格。
	if (i < 1000u){ // 共享缓冲共一千格。
		ivec3 imgCoordOffset = ivec3(floor(cameraPosition) - floor(previousCameraPosition)); // 体积随玩家移动的整格位移。
		ivec3 workGroupOffset = ivec3(gl_WorkGroupID * gl_WorkGroupSize) - 1; // 共享缓冲比工作组大一圈，起点减一。
		omniLpvPopulate(imgCoordOffset, workGroupOffset, i); // 搬第一格。
		omniLpvPopulate(imgCoordOffset, workGroupOffset, i + 1u); // 搬第二格。
	}
	barrier(); // 等所有线程读完共享缓冲，后面的邻居读取才完整。

	ivec3 imgCoord = ivec3(gl_GlobalInvocationID); // 本线程负责的体积格。
	if (any(greaterThanEqual(imgCoord, ivec3(int(omniLpvSide))))) return; // 超出边长直接退出。

	vec4 lightValue = vec4(0.0); // 本格最终的光。
	vec3 lightColor = vec3(0.0); // 本格自发光的颜色。
	vec3 tintColor = vec3(1.0); // 本格给穿过的光染的色。
	float lightRange = 0.0; // 本格自发光的强度。
	uint mixMask = 0xFFFFu; // 本格的方向掩码。

	uint blockId = omniVoxelShared[omniLpvSharedIndex(ivec3(gl_LocalInvocationID) + 1)]; // 本格的方块编号。
	if (blockId > 0u){ // 空气为零，跳过查表。
		uvec2 blockData = omniLpvBlockRow(blockId); // 读光表项。
		vec4 lightColorRange = unpackUnorm4x8(blockData.r); // 低字：光色与光强。
		lightColor = omniSrgbToLinear(lightColorRange.rgb); // 颜色转线性。
		lightRange = lightColorRange.a * 255.0; // 光强还原成格数。
		vec4 tintColorMask = unpackUnorm4x8(blockData.g); // 高字：染色与掩码。
		tintColor = omniSrgbToLinear(tintColorMask.rgb); // 染色也转线性。
		mixMask = (blockData.g >> 24) & 0xFFFFu; // 方向掩码。
	}

	if (any(greaterThan(tintColor, vec3(0.0)))){ // 只有还透光才做邻居混合。
		vec4 lightMixed = omniLpvMixNeighbours(ivec3(gl_LocalInvocationID), mixMask); // 混合六个邻居。
		lightMixed.rgb *= tintColor; // 按本格染色滤一遍，透光率零时这里归零，光就被挡住。
		lightValue += lightMixed; // 累加进本格。
	}

	if (lightRange > 0.0){ // 本格自己发光。
		vec3 hsv = omniRgbToHsv(lightColor); // 拆出颜色。
		hsv.z = exp2(lightRange) - 1.0; // 光强按指数放大，照 Eclipse `shadowcomp.csh:159`。
		lightValue.rgb += omniHsvToRgb(hsv); // 累加自发光。
	}

	vec4 encoded = omniLpvEncode(lightValue); // 按对数编码压住动态范围。
	if ((frameCounter % 2) == 0)
		imageStore(omniLpv1, imgCoord, encoded); // 偶数帧写第一张，片元下一帧从这两张里读最新的一张。
	else
		imageStore(omniLpv2, imgCoord, encoded); // 奇数帧写第二张。
#endif // 开关与能力条件结束。
}
#endif // shadowcomp 阶段结束。
#endif // 文件守卫结束。
