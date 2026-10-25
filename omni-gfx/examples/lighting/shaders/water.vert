#version 330 core
// 水面顶点阶段：把平面水片的水平坐标送到世界空间，高度固定为水面高度。
// 调用位置：主场景水面绘制；反射相机不画水面。
// 设计原因与取舍：水面是解析平面，不需要细分网格；波形只在片元阶段扰动法线，
// 这样反射与折射的屏幕坐标仍然来自同一张平面，不会因为顶点起伏而错位。
layout(location = 0) in vec2 aPosition; // 水平坐标 x、z。

uniform mat4 uViewProjection; // 当前相机视图投影。
uniform float uWaterLevel; // 水面高度。

out vec3 vWorldPosition; // 水面世界坐标。

void main()
{
    vWorldPosition = vec3(aPosition.x, uWaterLevel, aPosition.y); // 抬到水面高度。
    gl_Position = uViewProjection * vec4(vWorldPosition, 1.0); // 平面投影。
}
