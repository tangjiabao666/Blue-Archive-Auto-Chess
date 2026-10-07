shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// DSFX/FX_SHADER_AlphaBlend_0 with native HG constants. Alpha uses RED.
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec3 particle_tint = vec3(1.0);
uniform float material_intensity = 5.9921569824;
uniform float frame_index = 0.0;
uniform float roll = 0.0;
void vertex() {
    VERTEX.xy = mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll))) * VERTEX.xy;
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
    vec2 tile = vec2(mod(frame_index,2.0),floor(frame_index/2.0));
    vec4 sample_color = texture(atlas,(UV+tile)*0.5);
    ALBEDO = sample_color.rgb * particle_tint * material_intensity;
    ALPHA = clamp(sample_color.r,0.0,1.0);
}
