shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled;
// Native Step_0 variant: white main texture, mask eroded by custom stream X.
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform vec3 particle_tint = vec3(1.0);
uniform float material_intensity = 1.0;
uniform float threshold = 0.0;
uniform float roll = 0.0;
uniform float depth_offset = 0.0;
void vertex() {
    VERTEX.xy = mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll))) * VERTEX.xy;
    VERTEX.z += depth_offset;
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
    float mask_value = step(threshold,texture(mask_texture,UV).r);
    ALBEDO = mask_value*particle_tint*material_intensity;
    ALPHA = mask_value;
}
