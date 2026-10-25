#version 330 core
// 树干、树枝与岩石的顶点阶段：把世界坐标、法线、UV、颜色、风摆与材质编号传给片元。
// 调用位置：测试世界的主场景绘制与阴影绘制共用这组属性。
// 设计原因与取舍：树干与岩石都是不透明几何，法线与 UV 在 CPU 侧已经算好，
// 顶点阶段不做形变，只有叶片卡片的顶点阶段才需要风摆。
layout(location = 0) in vec3 aPosition; // 世界坐标。
layout(location = 1) in vec3 aNormal; // 世界空间法线。
layout(location = 2) in vec2 aUv; // 树皮的环向与纵向纹理坐标。
layout(location = 3) in vec3 aColor; // 逐顶点色调。
layout(location = 4) in float aSway; // 风摆权重，树干为零。
layout(location = 5) in float aMaterial; // 材质编号，五为树皮、二为岩石。

uniform mat4 uViewProjection; // 相机视图投影。
uniform float uTime; // 场景时间。
uniform float uWind; // 风摆幅度。

out vec3 vWorldPosition; // 世界坐标。
out vec3 vNormal; // 世界法线。
out vec2 vUv; // 纹理坐标。
out vec3 vColor; // 色调。
out float vMaterial; // 材质编号。
out float vSway; // 风摆权重。

void main()
{
    vec3 position = aPosition;
    float phase = aPosition.x * 0.62 + aPosition.z * 0.41; // 与叶片同一相位。
    float gust = 0.65 + 0.35 * sin(uTime * 0.37 + aPosition.x * 0.05);
    position.x += sin(uTime * 1.55 + phase) * 0.10 * aSway * uWind * gust;
    position.z += cos(uTime * 1.23 + phase * 1.31) * 0.07 * aSway * uWind * gust;
    vWorldPosition = position;
    vNormal = aNormal;
    vUv = aUv;
    vColor = aColor;
    vMaterial = aMaterial;
    vSway = aSway;
    gl_Position = uViewProjection * vec4(position, 1.0);
}
