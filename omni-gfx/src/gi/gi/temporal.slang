// 相机速度：区分远景与近景、手与世界，算出当前像素相对上一帧的屏幕位移。
float2 ogxGiCameraVelocity(float2 coord, float depth, bool isDh, float materialIds, OgxGiView view,
    bool disableHand, bool disablePlayer, float handDepth, float playerMaterial)
{
    float3 screenPos = float3(coord, depth); // 屏幕坐标加深度。
    float3 projection = float3(0.0); // 上一帧投影结果。
    if (isDh) // 远景像素用远景矩阵。
    {
        projection = float3(float2(view.dh_projection_inverse[0].x, view.dh_projection_inverse[1].y) * (screenPos * 2.0 - 1.0).xy, 0.0) + ogxMatrixTranslation(view.dh_projection_inverse); // 逆投影到视空间。
        projection /= view.dh_projection_inverse[2].w * (screenPos.z * 2.0 - 1.0) + view.dh_projection_inverse[3].w; // 透视除法。
        projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
        projection += view.camera_position - view.previous_camera_position; // 加相机世界位移。
        projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 世界转上一帧视空间。
    }
    else // 近景像素。
    {
        float3 ndc = screenPos * 2.0 - 1.0; // 转负一到一。
        projection = float3(float2(view.projection_inverse[0].x, view.projection_inverse[1].y) * ndc.xy, 0.0) + ogxMatrixTranslation(view.projection_inverse); // 逆投影到视空间。
        projection /= view.projection_inverse[2].w * ndc.z + view.projection_inverse[3].w; // 透视除法。
        bool isPlayer = materialIds == playerMaterial; // 玩家像素标记。
        if (disableHand && disablePlayer) // 手和玩家都不参与重投影。
        {
            if (depth >= 0.7 && !isPlayer) // 非玩家且较远。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
        else if (disableHand) // 只有手不参与。
        {
            if (depth >= 0.7) // 较远像素才重投影。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
        else if (disablePlayer) // 只有玩家不参与。
        {
            if (!isPlayer) // 非玩家像素。
            {
                if (depth < 0.7) // 手部固定深度偏移。
                {
                    projection += (ogxMatrixTranslation(view.previous_model_view) - ogxMatrixTranslation(view.model_view)) * handDepth;
                }
                else // 其他近景像素正常重投影。
                {
                    projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                    projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                    projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
                }
            }
        }
        else // 都参与重投影。
        {
            if (depth < 0.7) // 手部固定位移。
            {
                projection += (ogxMatrixTranslation(view.previous_model_view) - ogxMatrixTranslation(view.model_view)) * handDepth;
            }
            else // 其他近景像素正常重投影。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
    }
    float3 previousScreen = float3(view.previous_projection[0].x, view.previous_projection[1].y, view.previous_projection[2].z) * projection + ogxMatrixTranslation(view.previous_projection); // 上一帧投影的缩放与平移项。
    previousScreen = previousScreen / -projection.z * 0.5 + 0.5; // 透视除法与零到一换算，除数用投影前的深度。
    return coord - previousScreen.xy; // 返回屏幕位移。
}

// 全局光时间滤波：本帧反弹与历史帧按法线、深度和运动量混合，同时把法线与距离写回历史图。
float4 ogxGiTemporalFilter(float2 coord, int2 texelCoord, OgxGiView view,
    Sampler2D historyTexture, Sampler2D normalTexture, Sampler2D materialTexture, Sampler2D depthTexture, Sampler2D dhDepthTexture,
    Sampler2D shadowDepth0, Sampler2D shadowDepth1, Sampler2D shadowColor0, Sampler2D shadowColor1,
    float renderScale, bool has_dh, bool useDhAo, bool newVersion, bool leakFix, bool underwater,
    bool useSolidShadow, bool disableHand, bool disablePlayer, float handDepth, float playerMaterial,
    float radius, float falloff, int steps, float shadowMapResolution, float shadowBias, float2 noise)
{
    float4 prev = historyTexture.Load(int3(texelCoord, 0)); // 先取历史像素。
    float2 local = coord / renderScale; // 全局光渲染分辨率下的坐标。
    if (ogxEqual(ogxSaturate(local), local)) // 只在有效范围内处理。
    {
        int2 texel = int2(local * view.screen_size); // 对应的屏幕纹素。
        float currDepth = depthTexture.Load(int3(texel, 0)).x; // 本帧不透明深度。
        bool isDh = false; // 是否远景像素。
        if (has_dh && useDhAo && currDepth == 1.0) // 天空像素改读远景深度。
        {
            currDepth = dhDepthTexture.Load(int3(texel, 0)).x; // 远景深度。
            isDh = true; // 标记远景。
        }
        if (currDepth < 1.0) // 有几何才算反弹。
        {
            float4 data3 = normalTexture.Load(int3(texel, 0)); // 读法线光照图。
            float3 currNormal = ogxDecodeNormal(data3.xy); // 解出本帧法线。
            float3 currViewPos = ogxGiViewPos(local, currDepth, view.projection_inverse); // 还原视空间位置。
            if (isDh) // 远景用远景逆投影。
            {
                currViewPos = ogxGiViewPosDh(local, currDepth, view.dh_projection_inverse);
            }
            float3 gi = float3(0.0); // 本帧反弹。
            bool applyRsm = true; // 默认所有像素都反弹。
            if (newVersion) // 新版本按天光标记决定。
            {
                if (leakFix) // 只有接到天光或在水里才反弹。
                {
                    applyRsm = data3.w > 0.0 || underwater;
                }
            }
            else // 旧版本还要求像素足够远。
            {
                if (leakFix) // 较远且接到天光。
                {
                    applyRsm = currDepth > 0.7 && (data3.w > 0.0 || underwater);
                }
                else // 只要求较远。
                {
                    applyRsm = currDepth > 0.7;
                }
            }
            if (applyRsm) // 只有需要反弹的像素才采样阴影图。
            {
                gi = ogxGiRsm(currViewPos, currNormal, view, shadowDepth0, shadowDepth1, shadowColor0, shadowColor1,
                    radius, steps, falloff, shadowMapResolution, shadowBias, noise, useSolidShadow, leakFix, underwater); // 算一次反弹。
            }
            float materialIds = 0.0; // 不排除手或玩家时不需要读材质。
            if (disableHand || disablePlayer) // 只有需要排除时才读材质编号。
            {
                materialIds = floor(materialTexture.Load(int3(texel, 0)).b * 255.0);
            }
            float2 velocity = ogxGiCameraVelocity(local, currDepth, isDh, materialIds, view, disableHand, disablePlayer, handDepth, playerMaterial); // 屏幕位移。
            float2 prevCoord = local - velocity; // 映射到上一帧坐标。
            float2 clamped = clamp(prevCoord, float2(0.0), float2(1.0) - view.texel_size * 2.0); // 夹到画面内。
            if (ogxEqual(clamped, prevCoord)) // 历史坐标有效才做滤波。
            {
                float2 prevTexelCoord = prevCoord * renderScale * view.screen_size - 0.5; // 换成历史纹素坐标。
                float currDist = min(-currViewPos.z, 1000.0); // 本帧到相机的距离，限长避免远处权重异常。
                float3 cameraVelocity = ogxMatrixMulPoint(view.model_view, view.camera_position - view.previous_camera_position); // 相机速度转到视空间。
                float weightSum = 0.0; // 权重和。
                float3 prevGi = ogxGiHistorySample(currNormal, currDist, cameraVelocity, prevTexelCoord, renderScale,
                    historyTexture, normalTexture, view.screen_size, weightSum); // 取上一帧加权历史反弹。
                gi = lerp(gi, prevGi, 0.95 * weightSum); // 与历史混合。
            }
            prev = float4(ogxLinearToCurve3(gi), 0.0); // 编码回历史格式。
        }
    }
    local.x -= 1.0; // 顶行左侧一格存法线与距离。
    if (ogxEqual(ogxSaturate(local), local)) // 只在有效范围内处理。
    {
        int2 texel = int2(floor(local * view.screen_size)); // 对应的屏幕纹素。
        float depth = depthTexture.Load(int3(texel, 0)).x; // 不透明深度。
        bool isDh = false; // 远景标记。
        if (has_dh && useDhAo && depth == 1.0) // 天空像素改读远景深度。
        {
            depth = dhDepthTexture.Load(int3(texel, 0)).x; // 远景深度。
            isDh = true; // 标记远景。
        }
        if (depth < 1.0) // 有几何才写历史数据。
        {
            float3 normal = ogxDecodeNormal(normalTexture.Load(int3(texel, 0)).xy); // 解法线。
            float dist = 1.0 / ((depth * 2.0 - 1.0) * view.projection_inverse[2][3] + view.projection_inverse[3][3]); // 深度换米制距离。
            if (isDh) // 远景换算。
            {
                dist = 1.0 / ((depth * 2.0 - 1.0) * view.dh_projection_inverse[2][3] + view.dh_projection_inverse[3][3]);
            }
            prev = float4(normal * 0.5 + 0.5, dist * 0.001); // 法线压到零到一，距离缩小存进透明通道。
        }
        else // 天空像素没有有效历史。
        {
            prev = float4(float3(0.5), 0.0); // 写入中性值。
        }
    }
    return prev; // 返回本帧要写回历史图的数据。
}
