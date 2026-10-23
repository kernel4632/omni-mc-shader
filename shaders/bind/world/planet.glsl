/*
行星曲率的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/world/planet.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_WORLD_PLANET_INCLUDED
#define OMNI_BIND_WORLD_PLANET_INCLUDED
#include "/effects/world/planet.glsl"
/*
行星曲率：让地形、实体与水面随距相机的水平距离逐渐下沉，模拟站在星球表面看到的弯曲地平线。
来源：Eclipse 原实现，选项见 `references/Eclipse/shaders/lib/settings.glsl`，顶点公式见
  `references/Eclipse/shaders/dimensions/all_solid.vsh`、`all_translucent.vsh`、`all_particles.vsh`、
  `all_vanilla_emissives.vsh`、`world0/shadow.vsh`、`DH_solid.vsh`、`DH_translucent.vsh` 等多处顶点程序，逐字照搬。
调用位置：所有会画世界几何的顶点阶段，在算好顶点位置之后、投影到裁剪空间之前各调用一次：
  已经拿到相机相对世界坐标的阶段直接用 `omniPlanetCurvatureDrop`；只剩视空间位置的阶段用
  `omniPlanetCurvatureView`，普通绘制（实体、水面、远景、覆盖层）走一参版，阴影相机视空间走三参版。
可复制示例：
  `worldPos.y -= omniPlanetCurvatureDrop(worldPos.xz);` // 已有相机相对世界坐标，直接下沉纵向
  `omniPlanetCurvatureView(viewSpacePos);` // 相机矩阵视空间，就地下沉纵向
  `omniPlanetCurvatureView(shadowViewPos, mat3(shadowModelViewInverse), mat3(shadowModelView));` // 阴影相机视空间
关键设计原因与取舍：
  一、公式与 Eclipse 逐字一致：水平距离除以一百二十八得到 `curvature`，纵向下沉 `curvature` 平方乘强度。
    距离以相机为原点，同一个世界点只在相机移动时改变下沉量，模型之间保持相对关系。
  二、默认关闭。`OMNI_PLANET_CURVATURE` 不开时下沉量为零，默认画面与现在完全一致。
  三、只在顶点阶段算一次；片元阶段不重复，避免同一像素反复求距离。
  四、一致性靠“每个会画世界几何的顶点阶段都做同一次下沉”实现，Eclipse 不做额外的深度补偿。本项目已接入地形、
    实体（含方块、手持、蜘蛛眼）、水面、阴影（含远景阴影）、远景地形、远景水，以及覆盖层的粒子、线条、破坏、
    附魔光、信标光束与天气；只画天空的天体程序不做下沉。
*/


// 加载器输入声明；调用方通常已先引入，这里再引入一次由守卫去重，保证单独引用也能编译。
#include "/common/uniforms.glsl"

// 行星曲率的下沉量：由相机相对水平坐标算出这个顶点要沿纵向下沉多远。
// 为什么以相机为原点：曲率表示“离我越远越往下弯”，改用世界绝对坐标会随坐标漂移，模型之间会错位。
// 为什么与水平距离平方成正比：真实球面相对切面的高度亏损近似正比于水平距离平方，Eclipse 用同一写法。
float omniPlanetCurvatureDrop(vec2 horizontal){
	float amount = 0.0; // 下沉强度默认零，表示关闭。
	#if OMNI_PLANET_CURVATURE // 开启时才取玩家的强度。
		amount = OMNI_CURVATURE_AMOUNT; // 取玩家设置的曲率强度。
	#endif
	return gfx_planet_curvature_drop(horizontal, amount); // 公式在通用库。
}
// 视空间下沉版本：按调用方给定的一对互逆矩阵把视空间位置转到相机相对世界坐标，下沉纵向后再转回。
// 为什么把矩阵当作参数：不同阶段的视空间属于不同相机——普通绘制挂在 `gbufferModelView`，阴影挂在 `shadowModelView`；
//   抽成参数后它们共用同一份公式与下沉量，避免每个顶点程序各写一遍，导致数值对不上而出现接缝或阴影错位。
// 为什么先转世界坐标：下沉量按水平距离算，而视空间的横纵带着相机旋转，直接取分量会把距离算错。
void omniPlanetCurvatureView(inout vec3 viewSpacePos, mat3 viewToWorld, mat3 worldToView){
	vec3 relativeWorldPos = viewToWorld * viewSpacePos; // 视空间转相机相对世界坐标，只转方向不用平移。
	relativeWorldPos.y -= omniPlanetCurvatureDrop(relativeWorldPos.xz); // 按水平距离下沉纵向。
	viewSpacePos = worldToView * relativeWorldPos; // 再转回视空间，交给后续投影。
}
// 相机矩阵版本：普通绘制阶段（地形、实体、水面、远景、覆盖层）都挂在加载器相机矩阵上，直接用这一版。
void omniPlanetCurvatureView(inout vec3 viewSpacePos){
	omniPlanetCurvatureView(viewSpacePos, mat3(gbufferModelViewInverse), mat3(gbufferModelView)); // 用加载器的相机矩阵作转换。
}
#endif // OMNI_BIND_WORLD_PLANET_INCLUDED
