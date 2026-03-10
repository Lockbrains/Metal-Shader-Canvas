//
//  TutorialData.swift
//  macOSShaderCanvas
//
//  Built-in 9-step tutorial that teaches Metal Shading Language from scratch.
//
//  TUTORIAL DESIGN:
//  ────────────────
//  Each step provides:
//  - starterCode: MSL source with TODO comments for the student to fill in
//  - solutionCode: the complete working solution
//  - instructions: what to learn and how to approach the exercise
//  - goal: the visual outcome the student should achieve
//  - hint: a code snippet hint (shown on demand)
//
//  LESSON PROGRESSION:
//  ───────────────────
//  The lessons build on each other in a deliberate order:
//
//  1. Hello Fragment Shader  — output a solid color (understand float4 RGBA)
//  2. Visualize Normals      — use surface normals as color (understand interpolation)
//  3. Lambert Diffuse        — basic lighting with dot(N, L) (understand dot product)
//  4. Blinn-Phong Specular   — add highlights with half vector (understand specular)
//  5. Animating with Time    — use sin(time) for animation (understand uniforms)
//  6. Vertex Displacement    — deform mesh geometry (understand vertex shaders)
//  7. Fresnel Rim Lighting   — edge glow effect (understand view-dependent effects)
//  8. Post-Processing        — fullscreen vignette (understand texture sampling)
//  9. Final Challenge        — combine everything (no hints, write from scratch)
//
//  AI-GENERATED TUTORIALS:
//  ───────────────────────
//  The AIService can generate custom tutorial steps in the same TutorialStep format.
//  When AI tutorials are loaded, they replace this built-in data in ContentView.
//

import Foundation

/// A single step in the tutorial progression.
///
/// Each step targets a specific shader concept and provides both
/// starter code (with TODOs) and a complete solution.
struct TutorialStep: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let instructions: String
    let goal: String
    let hint: String
    let category: ShaderCategory
    let starterCode: String
    let solutionCode: String
}

/// Contains the built-in 9-step Metal shader tutorial.
struct TutorialData {
    static let steps: [TutorialStep] = [

        // MARK: - Lesson 1: Solid Color

        TutorialStep(
            id: 0,
            title: "Lesson 1: Hello, Fragment Shader",
            subtitle: "Output your first pixel color",
            instructions: """
            A fragment shader runs once per pixel on the mesh surface. \
            Its only job is to return a color as float4(r, g, b, a).

            Right now the shader returns white. \
            Change the return value to output a bright red color.
            """,
            goal: "Make the sphere turn red.",
            hint: "Red in RGBA is float4(1.0, 0.0, 0.0, 1.0)",
            category: .fragment,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                // TODO: Change this color to red!
                return float4(1.0, 1.0, 1.0, 1.0);
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                return float4(1.0, 0.0, 0.0, 1.0);
            }
            """
        ),

        // MARK: - Lesson 2: Gradient with Normals

        TutorialStep(
            id: 1,
            title: "Lesson 2: Visualize Normals",
            subtitle: "Use surface normals to create color",
            instructions: """
            The `in.normal` vector tells you which direction each point \
            on the surface is facing. Its x/y/z components range from -1 to 1.

            You can map normals to colors: remap each component from \
            [-1, 1] to [0, 1] using the formula: `value * 0.5 + 0.5`.

            This is a classic debugging technique used everywhere in graphics.
            """,
            goal: "Color the sphere based on its surface normals (rainbow-like pattern).",
            hint: "float3 color = in.normal * 0.5 + 0.5; then return float4(color, 1.0);",
            category: .fragment,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);

                // TODO: Map the normal vector from [-1,1] to [0,1] range
                // and use it as RGB color.
                float3 color = float3(1.0);

                return float4(color, 1.0);
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 color = N * 0.5 + 0.5;
                return float4(color, 1.0);
            }
            """
        ),

        // MARK: - Lesson 3: Lambert Diffuse

        TutorialStep(
            id: 2,
            title: "Lesson 3: Lambert Diffuse Lighting",
            subtitle: "The foundation of all lighting models",
            instructions: """
            Lambert's law: a surface is brightest when it faces the light \
            directly, and darkest when the light grazes it sideways.

            The formula is simple: `intensity = max(0, dot(N, L))`
            - N = surface normal (already provided)
            - L = light direction (try normalize(float3(1, 1, 1)))
            - dot(N, L) gives the cosine of the angle between them
            - max(0, ...) prevents negative values (backface)

            Multiply a base color by this intensity.
            """,
            goal: "Implement basic Lambert diffuse lighting with a visible light/shadow transition.",
            hint: "float diffuse = max(0.0, dot(N, L)); return float4(baseColor * diffuse, 1.0);",
            category: .fragment,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float3 baseColor = float3(0.8, 0.3, 0.2);

                // TODO: Calculate Lambert diffuse intensity using dot(N, L)
                // Remember to clamp negative values with max()
                float diffuse = 1.0;

                return float4(baseColor * diffuse, 1.0);
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float3 baseColor = float3(0.8, 0.3, 0.2);

                float diffuse = max(0.0, dot(N, L));

                return float4(baseColor * diffuse, 1.0);
            }
            """
        ),

        // MARK: - Lesson 4: Blinn-Phong Specular

        TutorialStep(
            id: 3,
            title: "Lesson 4: Blinn-Phong Specular",
            subtitle: "Add shiny highlights to your lighting",
            instructions: """
            Blinn-Phong adds a specular highlight on top of diffuse.

            The key idea: compute the "half vector" H = normalize(L + V), \
            then measure how closely the surface normal aligns with H.

            Formula: `specular = pow(max(0, dot(N, H)), shininess)`
            - V = view direction (use float3(0, 0, 1) since camera faces +Z)
            - Higher shininess = smaller, tighter highlight
            - Try shininess = 32 or 64

            Final color = baseColor * (ambient + diffuse) + specular
            """,
            goal: "Add a white specular highlight to the Lambert lighting from Lesson 3.",
            hint: "float3 H = normalize(L + V); float spec = pow(max(0.0, dot(N, H)), 64.0);",
            category: .fragment,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float3 V = normalize(float3(0.0, 0.0, 1.0));
                float3 baseColor = float3(0.3, 0.5, 0.9);

                float ambient = 0.1;
                float diffuse = max(0.0, dot(N, L));

                // TODO: Calculate the half vector H = normalize(L + V)
                // Then compute specular = pow(max(0, dot(N, H)), shininess)
                float specular = 0.0;

                float3 color = baseColor * (ambient + diffuse) + float3(1.0) * specular;
                return float4(color, 1.0);
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float3 V = normalize(float3(0.0, 0.0, 1.0));
                float3 baseColor = float3(0.3, 0.5, 0.9);

                float ambient = 0.1;
                float diffuse = max(0.0, dot(N, L));

                float3 H = normalize(L + V);
                float specular = pow(max(0.0, dot(N, H)), 64.0);

                float3 color = baseColor * (ambient + diffuse) + float3(1.0) * specular;
                return float4(color, 1.0);
            }
            """
        ),

        // MARK: - Lesson 5: Time Animation

        TutorialStep(
            id: 4,
            title: "Lesson 5: Animating with Time",
            subtitle: "Bring your shader to life",
            instructions: """
            The `in.time` uniform gives you elapsed seconds from the CPU. \
            Feed it into sin/cos to create smooth oscillations.

            Try making the color pulse over time:
            - Use sin(in.time) to oscillate a value between -1 and 1
            - Remap to [0, 1] with `* 0.5 + 0.5`
            - Blend between two colors using mix()

            Formula: `mix(colorA, colorB, t)` blends A→B as t goes 0→1.
            """,
            goal: "Create a smooth color animation that cycles between two colors over time.",
            hint: "float t = sin(in.time) * 0.5 + 0.5; float3 color = mix(colorA, colorB, t);",
            category: .fragment,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float diffuse = max(0.2, dot(N, L));

                float3 colorA = float3(1.0, 0.3, 0.2);
                float3 colorB = float3(0.2, 0.5, 1.0);

                // TODO: Use sin(in.time) to create a smooth 0-1 oscillation
                // Then use mix(colorA, colorB, t) to blend between the two colors
                float t = 0.5;
                float3 color = mix(colorA, colorB, t);

                return float4(color * diffuse, 1.0);
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float diffuse = max(0.2, dot(N, L));

                float3 colorA = float3(1.0, 0.3, 0.2);
                float3 colorB = float3(0.2, 0.5, 1.0);

                float t = sin(in.time) * 0.5 + 0.5;
                float3 color = mix(colorA, colorB, t);

                return float4(color * diffuse, 1.0);
            }
            """
        ),

        // MARK: - Lesson 6: Vertex Displacement

        TutorialStep(
            id: 5,
            title: "Lesson 6: Your First Vertex Shader",
            subtitle: "Deform the mesh itself",
            instructions: """
            A vertex shader transforms each vertex POSITION before it gets drawn. \
            Unlike fragment shaders (which color pixels), vertex shaders move geometry.

            The key line is: modify `in.position` before transforming it by the MVP matrix.

            Try adding a sine wave displacement along Y:
            `pos.y += sin(pos.x * frequency + time * speed) * amplitude`

            This creates a wave that travels across the mesh surface.
            """,
            goal: "Make the sphere wobble with a sine wave deformation along the Y axis.",
            hint: "pos.y += sin(pos.x * 5.0 + uniforms.time * 3.0) * 0.15;",
            category: .vertex,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexIn {
                float3 position [[attribute(0)]];
                float3 normal [[attribute(1)]];
                float2 texCoord [[attribute(2)]];
            };

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            struct Uniforms {
                float4x4 modelViewProjectionMatrix;
                float time;
            };

            vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
                VertexOut out;
                float3 pos = in.position;

                // TODO: Add sine wave displacement to pos.y
                // Use sin(pos.x * frequency + uniforms.time * speed) * amplitude
                // Try frequency=5, speed=3, amplitude=0.15

                out.position = uniforms.modelViewProjectionMatrix * float4(pos, 1.0);
                out.normal = in.normal;
                out.texCoord = in.texCoord;
                out.time = uniforms.time;
                return out;
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexIn {
                float3 position [[attribute(0)]];
                float3 normal [[attribute(1)]];
                float2 texCoord [[attribute(2)]];
            };

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            struct Uniforms {
                float4x4 modelViewProjectionMatrix;
                float time;
            };

            vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
                VertexOut out;
                float3 pos = in.position;

                pos.y += sin(pos.x * 5.0 + uniforms.time * 3.0) * 0.15
                       + cos(pos.z * 5.0 + uniforms.time * 3.0) * 0.15;

                out.position = uniforms.modelViewProjectionMatrix * float4(pos, 1.0);
                out.normal = in.normal;
                out.texCoord = in.texCoord;
                out.time = uniforms.time;
                return out;
            }
            """
        ),

        // MARK: - Lesson 7: Fresnel Rim Light

        TutorialStep(
            id: 6,
            title: "Lesson 7: Fresnel & Rim Lighting",
            subtitle: "Highlight the silhouette edges",
            instructions: """
            The Fresnel effect makes surfaces brighter at glancing angles. \
            Think of how the edge of a glass or a lake glows.

            Formula: `fresnel = pow(1.0 - max(0, dot(N, V)), exponent)`
            - When N and V are parallel (facing camera): dot≈1, fresnel≈0
            - When N and V are perpendicular (edge): dot≈0, fresnel≈1

            Add the fresnel term as a rim light color on top of your diffuse.
            """,
            goal: "Add a glowing blue rim light around the edges of the sphere.",
            hint: "float rim = pow(1.0 - max(0.0, dot(N, V)), 3.0); color += rimColor * rim;",
            category: .fragment,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float3 V = normalize(float3(0.0, 0.0, 1.0));

                float3 baseColor = float3(0.15, 0.1, 0.2);
                float3 rimColor = float3(0.3, 0.6, 1.0);
                float diffuse = max(0.0, dot(N, L));

                // TODO: Calculate the Fresnel rim term
                // fresnel = pow(1.0 - max(0.0, dot(N, V)), exponent)
                // Try exponent = 3.0
                float rim = 0.0;

                float3 color = baseColor * (0.1 + diffuse) + rimColor * rim;
                return float4(color, 1.0);
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float3 V = normalize(float3(0.0, 0.0, 1.0));

                float3 baseColor = float3(0.15, 0.1, 0.2);
                float3 rimColor = float3(0.3, 0.6, 1.0);
                float diffuse = max(0.0, dot(N, L));

                float rim = pow(1.0 - max(0.0, dot(N, V)), 3.0);

                float3 color = baseColor * (0.1 + diffuse) + rimColor * rim;
                return float4(color, 1.0);
            }
            """
        ),

        // MARK: - Lesson 8: Post-Processing

        TutorialStep(
            id: 7,
            title: "Lesson 8: Post-Processing — Vignette",
            subtitle: "Apply effects to the entire screen",
            instructions: """
            Post-processing shaders read the rendered image as a texture \
            and modify it. They run on a fullscreen triangle AFTER the mesh is drawn.

            `inTexture.sample(sampler, uv)` reads a pixel from the previous pass.

            A vignette darkens the screen edges:
            1. Calculate distance from center: `d = length(uv - 0.5)`
            2. Create a falloff: `vignette = smoothstep(outerRadius, innerRadius, d)`
            3. Multiply the base color by the vignette mask
            """,
            goal: "Add a circular vignette that darkens the edges of the screen.",
            hint: "float d = length(uv - 0.5); float vig = smoothstep(0.7, 0.3, d); return baseColor * vig;",
            category: .fullscreen,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float2 texCoord;
                float time;
            };

            struct Uniforms {
                float4x4 modelViewProjectionMatrix;
                float time;
            };

            vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
                VertexOut out;
                float2 positions[3] = {
                    float2(-1.0, -1.0),
                    float2( 3.0, -1.0),
                    float2(-1.0,  3.0)
                };
                out.position = float4(positions[vertexID], 0.0, 1.0);
                out.texCoord = positions[vertexID] * 0.5 + 0.5;
                out.texCoord.y = 1.0 - out.texCoord.y;
                out.time = uniforms.time;
                return out;
            }

            fragment float4 fragment_main(VertexOut in [[stage_in]],
                                          texture2d<float> inTexture [[texture(0)]]) {
                constexpr sampler s(address::clamp_to_edge, filter::linear);
                float2 uv = in.texCoord;
                float4 baseColor = inTexture.sample(s, uv);

                // TODO: Calculate distance from UV center (0.5, 0.5)
                // Use smoothstep(outerEdge, innerEdge, distance) to create the mask
                // Multiply baseColor by the mask
                float vignette = 1.0;

                return baseColor * vignette;
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float2 texCoord;
                float time;
            };

            struct Uniforms {
                float4x4 modelViewProjectionMatrix;
                float time;
            };

            vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
                VertexOut out;
                float2 positions[3] = {
                    float2(-1.0, -1.0),
                    float2( 3.0, -1.0),
                    float2(-1.0,  3.0)
                };
                out.position = float4(positions[vertexID], 0.0, 1.0);
                out.texCoord = positions[vertexID] * 0.5 + 0.5;
                out.texCoord.y = 1.0 - out.texCoord.y;
                out.time = uniforms.time;
                return out;
            }

            fragment float4 fragment_main(VertexOut in [[stage_in]],
                                          texture2d<float> inTexture [[texture(0)]]) {
                constexpr sampler s(address::clamp_to_edge, filter::linear);
                float2 uv = in.texCoord;
                float4 baseColor = inTexture.sample(s, uv);

                float d = length(uv - 0.5);
                float vignette = smoothstep(0.7, 0.3, d);

                return baseColor * vignette;
            }
            """
        ),

        // MARK: - Lesson 9: Putting It All Together

        TutorialStep(
            id: 8,
            title: "Lesson 9: Final Challenge",
            subtitle: "Combine everything you've learned",
            instructions: """
            Congratulations — you've learned the three pillars of real-time shading!

            For this final challenge, write a fragment shader that combines:
            1. Diffuse lighting (Lesson 3)
            2. Specular highlights (Lesson 4)
            3. Time-based color animation (Lesson 5)
            4. Fresnel rim lighting (Lesson 7)

            No TODO markers this time — write it from scratch! \
            You have all the tools. The solution shows one possible approach.
            """,
            goal: "Create a fully lit, animated shader with diffuse + specular + rim + time animation.",
            hint: "Combine all the techniques: Lambert diffuse, Blinn-Phong specular, Fresnel rim, and sin(time) animation.",
            category: .fragment,
            starterCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                // This is your blank canvas.
                // Combine everything you've learned:
                //   - Normals, dot product, Lambert diffuse
                //   - Blinn-Phong specular (half vector)
                //   - Time animation with sin/cos
                //   - Fresnel rim lighting
                //
                // Write your shader from scratch!

                return float4(1.0, 1.0, 1.0, 1.0);
            }
            """,
            solutionCode: """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float2 texCoord;
                float time;
            };

            fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                float3 N = normalize(in.normal);
                float3 L = normalize(float3(1.0, 1.0, 1.0));
                float3 V = normalize(float3(0.0, 0.0, 1.0));
                float3 H = normalize(L + V);

                // Animated base color
                float t = sin(in.time * 0.8) * 0.5 + 0.5;
                float3 baseColor = mix(float3(0.9, 0.3, 0.2), float3(0.2, 0.4, 0.9), t);

                // Lighting
                float ambient = 0.08;
                float diffuse = max(0.0, dot(N, L));
                float specular = pow(max(0.0, dot(N, H)), 48.0);

                // Fresnel rim
                float rim = pow(1.0 - max(0.0, dot(N, V)), 3.0);
                float3 rimColor = float3(0.4, 0.7, 1.0);

                float3 color = baseColor * (ambient + diffuse)
                             + float3(1.0) * specular * 0.6
                             + rimColor * rim * 0.5;

                return float4(color, 1.0);
            }
            """
        ),
    ]
}
