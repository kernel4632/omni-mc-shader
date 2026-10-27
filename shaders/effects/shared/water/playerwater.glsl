/*
效果文件 `effects/shared/water/playerwater.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shared/water/playerwater.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_PLAYERWATER_INCLUDED
#define OMNI_PLAYERWATER_INCLUDED
/*
玩家交互水面：玩家在水里移动时，水面从玩家处持续向外推出一圈圈涟漪。
来源：Eclipse `dimensions/all_translucent.fsh` 第 802 到 827 行的 `WATER_INTERACTION == 1`「简单」模式，
  波形公式逐行搬运；入水位置、入水速度与入水时刻三个输入改由本项目的现算量顶替，原因见下。
调用位置：本文件由 `effects/water/water.glsl` 引入；`GetWavesNormal` 算完基础波法线后调用本文件的
  `PlayerWaterRipple`，把涟漪高度叠到波法线上。选项 `OMNI_PLAYER_WATER` 与 `OMNI_PLAYER_WATER_STRENGTH`
  定义在同目录 `water.glsl` 的选项区，本文件不再重复声明。
可复制示例：`float ripple = PlayerWaterRipple(worldPos);`  传入水面片元的世界位置，得到零到一的涟漪高度。
设计原因与取舍：
  一、Eclipse 原效果用 Iris 表达式量冻结「入水那一刻的位置、时间、速度」，跨帧把三个值记住；本项目的
     中间量只能写在 `#define` 里，拿不到这种跨帧冻结值，所以三个量都改成当场能算的：位置用相机世界位置
     `cameraPosition`，速度用 `(cameraPosition - previousCameraPosition) / frameTime`，时间用累计秒数的周期相位。
  二、原效果用 `(当前秒数 - 入水秒数)` 让一圈涟漪只出现一次、扩散到最远处后消失；这里拿不到入水秒数，
     改用周期相位，让涟漪连续向外推出，读起来像玩家带起的一串水波，代价是中心会周期性冒出新环。
  三、只处理玩家相机。Eclipse 里生物扰动走 `WATER_INTERACTION == 2` 的波浪模拟，那套依赖计算着色器与
     多张模拟缓冲，超出本项目当前范围，本次未移植。
  四、入参必须是世界坐标：`caustics.glsl` 传入的是波浪空间坐标，离相机上千格，涟漪自然不触发。
*/

#if OMNI_PLAYER_WATER > 0 // 选项关闭时整段不参与编译，默认画面完全不受影响。

// 涟漪几何常数，取自 Eclipse 原实现；写成常数让每个程序的代价与表现一致。
#define PLAYER_WATER_MAX_DIST 3.5 // 涟漪最远扩散半径，单位米，原实现取值。
#define PLAYER_WATER_RING_SPEED 2.15 // 涟漪每秒向外扩散的距离，原实现取值。
#define PLAYER_WATER_RING_WIDTH 0.2 // 涟漪环的宽度，原实现取值。
#define PLAYER_WATER_PERIOD 2.0 // 一圈涟漪从中心扩到最远处的周期，约等于最远距离除以扩散速度。

// 求玩家在水面某处带起的涟漪高度：以相机为中心，按玩家速度给出一圈向外扩散的凸起。
// 返回零到一，调用方把它当成把波法线朝上推的权重；不在水里或超出半径时直接返回零。
float PlayerWaterRipple(vec3 worldPos){
	if (isEyeInWater != 1) return 0.0; // 眼睛不在水里就不出涟漪：本项目拿不到出水时刻，在岸上也画会留下永不消退的环。

	float distFromPlayer = length(worldPos - cameraPosition); // 水面片元到玩家的直线距离。
	if (distFromPlayer >= PLAYER_WATER_MAX_DIST) return 0.0; // 环外不做任何计算，省掉后面的开销。

	vec3 playerVelocity = (cameraPosition - previousCameraPosition) / max(frameTime, 1e-4); // 玩家每秒位移，等价于 Eclipse 的 `currentVelocity / frameTime`。

	float newTime = mod(frameTimeCounter, PLAYER_WATER_PERIOD) * PLAYER_WATER_RING_SPEED; // 用周期相位代替「距入水时刻的秒数」。

	float smoothDist = smoothstep(PLAYER_WATER_MAX_DIST, 0.0, distFromPlayer); // 越靠近玩家涟漪越强，最远处归零。
	float waveHeight = 0.3 * smoothstep(2.0, 20.0, length(playerVelocity)) + 0.5; // 移动越快涟漪越高；静止也留一半，原实现如此。

	float ring = smoothstep(newTime - PLAYER_WATER_RING_WIDTH, newTime, distFromPlayer - 0.1) // 环的内侧边界。
	           * smoothstep(newTime + PLAYER_WATER_RING_WIDTH, newTime, distFromPlayer - 0.1); // 环的外侧边界，两条相乘得到一个窄环。

	return waveHeight * ring * smoothDist * OMNI_PLAYER_WATER_STRENGTH; // 按强度选项缩放后返回涟漪高度。
}
#endif // 玩家交互水面选项结束。
#endif // OMNI_PLAYERWATER_INCLUDED
