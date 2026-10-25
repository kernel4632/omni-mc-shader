#version 330 core
// 地表顶点阶段：把地形与简单物体的位置、法线、反照率与粗糙度送到片元阶段。
// 调用位置：主场景与水面反射的地形、球、方块与立石绘制。
// 设计原因与取舍：所有物体共用一种交错格式，一个程序就能画完；材质差异只在顶点数据里，
// 不引入第二套材质系统，也就不会出现某个物体忘记接光照的分支。
layout(location = 0) in vec3 aPosition; // 世界坐标。
layout(location = 1) in vec3 aNormal; // 世界法线。
layout(location = 2) in vec3 aAlbedo; // 线性反照率。
layout(location = 3) in float aRoughness; // 粗糙度。
layout(location = 4) in float aMetallic; // 金属度。

uniform mat4 uViewProjection; // 当前相机或反射相机的视图投影。

out vec3 vWorldPosition; // 世界坐标。
out vec3 vNormal; // 世界法线。
out vec3 vAlbedo; // 线性反照率。
out float vRoughness; // 粗糙度。
out float vMetallic; // 金属度。

void main()
{
    vWorldPosition = aPosition; // 世界坐标直接传递。
    vNormal = aNormal; // 法线已经是世界空间。
    vAlbedo = aAlbedo; // 颜色保持线性。
    vRoughness = aRoughness; // 粗糙度直接传递。
    vMetallic = aMetallic; // 金属度直接传递。
    gl_Position = uViewProjection * vec4(aPosition, 1.0); // 常规投影。
}
