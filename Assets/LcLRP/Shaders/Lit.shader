Shader "LcLRP/Lit"
{
    Properties
    {
        // 这里是因为Unity的硬编码造成的,烘焙的半透明属性必须是_MainTex、_Color属性。。。。
        // 所以这里另外创建两个属性，通过c#把_BaseMap _BaseColor的值拷贝到_MainTex、_Color
        [HideInInspector] _MainTex ("Texture for Lightmap", 2D) = "white" { }
        [HideInInspector] _Color ("Color for Lightmap", Color) = (0.5, 0.5, 0.5, 1.0)

        _BaseMap ("Texture", 2D) = "white" { }
        _BaseColor ("Color", Color) = (0.5, 0.5, 0.5, 1.0)
        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        [Toggle(_CLIPPING)] _Clipping ("Alpha Clipping", Float) = 0
        [KeywordEnum(On, Clip, Dither, Off)] _Shadows ("Shadows", Float) = 0
        [Toggle(_RECEIVE_SHADOWS)] _ReceiveShadows ("Receive Shadows", Float) = 1

        [Toggle(_NORMAL_MAP)] _NormalMapToggle ("Normal Map", Float) = 0
        [NoScaleOffset] _NormalMap ("Normals", 2D) = "bump" { }
        _NormalScale ("Normal Scale", Range(0, 1)) = 1

        [Toggle(_MASK_MAP)] _MaskMapToggle ("Mask Map", Float) = 0
        [NoScaleOffset] _MaskMap ("Mask ()", 2D) = "white" { }
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _Occlusion ("Occlusion", Range(0, 1)) = 1
        _Fresnel ("Fresnel", Range(0, 1)) = 1

        [NoScaleOffset] _EmissionMap ("Emission", 2D) = "white" { }
        [HDR] _EmissionColor ("Emission", Color) = (0.0, 0.0, 0.0, 0.0)

        [Toggle(_DETAIL_MAP)] _DetailMapToggle ("Detail Maps", Float) = 0
        _DetailMap ("Details", 2D) = "linearGrey" { }
        _DetailAlbedo ("Detail Albedo", Range(0, 1)) = 1
        _DetailSmoothness ("Detail Smoothness", Range(0, 1)) = 1
        [NoScaleOffset] _DetailNormalMap ("Detail Normals", 2D) = "bump" { }
        _DetailNormalScale ("Detail Normal Scale", Range(0, 1)) = 1

        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 0
        [Enum(Off, 0, On, 1)] _ZWrite ("Z Write", Float) = 1
        [Toggle(_PREMULTIPLY_ALPHA)] _PremulAlpha ("Premultiply Alpha", Float) = 0
    }
    
    SubShader
    {
        HLSLINCLUDE
        #include "../ShaderLibrary/Common.hlsl"
        #include "LitInput.hlsl"
        ENDHLSL
        
        Pass
        {
            Tags { "LightMode" = "LcLLit" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            HLSLPROGRAM
            #pragma target 3.5

            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma shader_feature _CLIPPING
            #pragma shader_feature _PREMULTIPLY_ALPHA
            #pragma shader_feature _RECEIVE_SHADOWS
            #pragma shader_feature _NORMAL_MAP
            #pragma shader_feature _MASK_MAP
            #pragma shader_feature _DETAIL_MAP

            #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
            #pragma multi_compile _ _CASCADE_BLEND_SOFT _CASCADE_BLEND_DITHER
            #pragma multi_compile _ _SHADOW_MASK_DISTANCE
            #pragma multi_compile _ LIGHTMAP_ON
            
            #include "../ShaderLibrary/Common.hlsl"
            #include "LitPass.hlsl"

            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment
            ENDHLSL
        }


        Pass
        {
            Tags { "LightMode" = "ShadowCaster" }

            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.5
            #pragma shader_feature _ _SHADOWS_CLIP _SHADOWS_DITHER
            #pragma multi_compile_instancing
            #pragma vertex ShadowCasterPassVertex
            #pragma fragment ShadowCasterPassFragment
            #include "ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Tags { "LightMode" = "Meta" }

            Cull Off

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex MetaPassVertex
            #pragma fragment MetaPassFragment
              #include "../ShaderLibrary/Common.hlsl"
            #include "MetaPass.hlsl"
            ENDHLSL
        }
    }
    CustomEditor "LcLShaderGUI"
}