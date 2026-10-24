#version 330 core
// 全屏三角形顶点阶段：不绑定顶点缓冲，直接用顶点编号铺满屏幕。
// 调用位置：天空、后期与立方体贴图渲染共用。
void main()
{
    vec2 corner = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));  // 三个顶点覆盖整个屏幕。
    gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);  // 零到二映射到裁剪空间的负一到一。
}
