#ifndef LCL_SHADOWS_INCLUDED
#define LCL_SHADOWS_INCLUDED

#include "../ShaderLibrary/Surface.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"

#if defined(_DIRECTIONAL_PCF3)
    #define DIRECTIONAL_FILTER_SAMPLES 4
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_DIRECTIONAL_PCF5)
    #define DIRECTIONAL_FILTER_SAMPLES 9
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_DIRECTIONAL_PCF7)
    #define DIRECTIONAL_FILTER_SAMPLES 16
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

// 最大平行光阴影数量
#define MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT 4
// 级联阴影最大数量
#define MAX_CASCADE_COUNT 4

TEXTURE2D_SHADOW(_DirectionalShadowAtlas);
#define SHADOW_SAMPLER sampler_linear_clamp_compare
SAMPLER_CMP(SHADOW_SAMPLER);
CBUFFER_START(_CustomShadows)
    int _CascadeCount;
    float4 _CascadeCullingSpheres[MAX_CASCADE_COUNT];
    float4 _CascadeData[MAX_CASCADE_COUNT];
    float4x4 _DirectionalShadowMatrices [MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];
    float4 _ShadowAtlasSize;
    // float _ShadowDistance;
    float4 _ShadowDistanceFade;
CBUFFER_END



struct ShadowMask
{
    bool distance;
    float4 shadows;
};
struct ShadowData
{
    int cascadeIndex;
    // 级联混合值(为了解决PCF级联边界过渡太明显)
    float cascadeBlend;
    float strength;
    ShadowMask shadowMask;
};



// 当超出最大级联阴影范围时,计算一个淡化的平滑效果,避免生硬的阴影边缘痕迹
float FadedShadowStrength(float distance, float scale, float fade)
{
    return saturate((1.0 - distance * scale) * fade);
}

ShadowData GetShadowData(Surface surfaceWS)
{
    ShadowData data;
    data.shadowMask.distance = false;
    data.shadowMask.shadows = 1.0;
    data.cascadeBlend = 1.0;
    // data.strength = surfaceWS.depth < _ShadowDistance ? 1.0 : 0.0;
    data.strength = FadedShadowStrength(surfaceWS.depth, _ShadowDistanceFade.x, _ShadowDistanceFade.y);
    int i;
    for (i = 0; i < _CascadeCount; i++)
    {
        float4 sphere = _CascadeCullingSpheres[i];
        // 求点到级联球距离,判断点是否在级联范围内,从而确定用哪个等级的ShadowMap
        float distanceSqr = DistanceSquared(surfaceWS.position, sphere.xyz);
        if (distanceSqr < sphere.w)
        {
            float fade = FadedShadowStrength(distanceSqr, _CascadeData[i].x, _ShadowDistanceFade.z);
            if (i == _CascadeCount - 1)
            {
                // 淡化最后一个级联
                data.strength *= fade;
            }
            else
            {
                data.cascadeBlend = fade;
            }
            break;
        }
    }
    // 如果超出了最后一个级联,那么设置为0(即不采样Shadow Map)
    if (i == _CascadeCount)
    {
        data.strength = 0.0;
    }
    // 级联抖动混合
    #if defined(_CASCADE_BLEND_DITHER)
        // 相当于一个随机值,如果小于抖动值,就采样下一级联阴影,否则采样当前级联阴影
        else if (data.cascadeBlend < surfaceWS.dither)
        {
            i += 1;
        }
    #endif
    // 级联软混合
    #if !defined(_CASCADE_BLEND_SOFT)
        data.cascadeBlend = 1.0;
    #endif

    data.cascadeIndex = i;
    return data;
}

struct DirectionalShadowData
{
    float strength;
    int tileIndex;
    float normalBias;
    int shadowMaskChannel;
};


// 采样阴影图集
float SampleDirectionalShadowAtlas(float3 positionSTS)
{
    return SAMPLE_TEXTURE2D_SHADOW(_DirectionalShadowAtlas, SHADOW_SAMPLER, positionSTS);
}
// PCF
float FilterDirectionalShadow(float3 positionSTS)
{
    #if defined(DIRECTIONAL_FILTER_SETUP)
        float weights[DIRECTIONAL_FILTER_SAMPLES];
        float2 positions[DIRECTIONAL_FILTER_SAMPLES];
        float4 size = _ShadowAtlasSize.yyxx;
        DIRECTIONAL_FILTER_SETUP(size, positionSTS.xy, weights, positions);
        float shadow = 0;
        for (int i = 0; i < DIRECTIONAL_FILTER_SAMPLES; i++)
        {
            shadow += weights[i] * SampleDirectionalShadowAtlas(
                float3(positions[i].xy, positionSTS.z)
            );
        }
        return shadow;
    #else
        return SampleDirectionalShadowAtlas(positionSTS);
    #endif
}


float GetCascadedShadow(DirectionalShadowData directional, ShadowData shadowData, Surface surfaceWS)
{
    // 沿着法线偏移
    float3 normalBias = surfaceWS.interpolatedNormal * (directional.normalBias * _CascadeData[shadowData.cascadeIndex].y);
    float3 positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex], float4(surfaceWS.position + normalBias, 1.0)).xyz;
    // float shadow = SampleDirectionalShadowAtlas(positionSTS);
    float shadow = FilterDirectionalShadow(positionSTS);

    // 级联软混合模式
    if (shadowData.cascadeBlend < 1.0)
    {
        // 处于级联阴影过渡处, 和下一个级联做一个插值混合.
        normalBias = surfaceWS.interpolatedNormal * (directional.normalBias * _CascadeData[shadowData.cascadeIndex + 1].y);
        positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex + 1], float4(surfaceWS.position + normalBias, 1.0)).xyz;
        shadow = lerp(FilterDirectionalShadow(positionSTS), shadow, shadowData.cascadeBlend);
    }
    return shadow;
}

float GetBakedShadow(ShadowMask mask, int channel)
{
    float shadow = 1.0;
    // 开启了Distance Mode
    if (mask.distance)
    {
        if (channel >= 0)
        {
            shadow = mask.shadows[channel];
        }
    }
    return shadow;
}
float GetBakedShadow(ShadowMask mask, int channel, float strength)
{
    if (mask.distance)
    {
        return lerp(1.0, GetBakedShadow(mask, channel), strength);
    }
    return 1.0;
}
// 混合烘焙阴影和实时阴影
float MixBakedAndRealtimeShadows(ShadowData shadowData, float shadow, int shadowMaskChannel, float strength)
{
    float baked = GetBakedShadow(shadowData.shadowMask, shadowMaskChannel);
    if (shadowData.shadowMask.distance)
    {
        shadow = lerp(baked, shadow, shadowData.strength);
        return lerp(1.0, shadow, strength);
    }
    return lerp(1.0, shadow, strength * shadowData.strength);
}

// 阴影衰减
float GetDirectionalShadowAttenuation(DirectionalShadowData  directional, ShadowData shadowData, Surface surfaceWS)
{
    #if !defined(_RECEIVE_SHADOWS)
        return 1.0;
    #endif
    float shadow;
    // 阴影强度小于等于0时不采样Shadow Map
    if (directional.strength * shadowData.strength <= 0.0)
    {
        shadow = GetBakedShadow(shadowData.shadowMask, directional.shadowMaskChannel, abs(directional.strength));
    }
    else
    {
        shadow = GetCascadedShadow(directional, shadowData, surfaceWS);
        shadow = MixBakedAndRealtimeShadows(shadowData, shadow, directional.shadowMaskChannel, directional.strength);
    }
    return shadow;
}



#endif