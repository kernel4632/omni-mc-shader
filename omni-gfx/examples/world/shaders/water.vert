#version 330 core
// 水面顶点阶段：一张大平面覆盖海面，把世界坐标传给片元做波形。
// 调用位置：测试世界的水面绘制；平面不随相机移动，保证远处海岸线稳定。
layout(location = 0) in vec2 aPosition;  // 平面上的横向与纵向坐标。

uniform mat4 uViewProjection;  // 相机视图投影矩阵。
uniform float uWaterLevel;  // 海平面高度。

out vec3 vWorldPosition;  // 片元阶段用来算波形与视线。

void main()
{
    vec3 world = vec3(aPosition.x, uWaterLevel, aPosition.y);  // 平面顶点放到海平面。
    vWorldPosition = world;  // 传递世界坐标。
    gl_Position = uViewProjection * vec4(world, 1.0);  // 投影到裁剪空间。
}
