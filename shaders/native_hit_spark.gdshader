shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled;
// Native AlphaBlend_Add: white main RGB, red channel opacity, multiply=3.
uniform sampler2D spark_texture : source_color, filter_linear, repeat_enable;
uniform vec3 particle_tint = vec3(1.0,0.4768409133,0.0);
uniform vec3 direction = vec3(1.0,0.0,0.0);
uniform float material_intensity = 4.2370948792;
void vertex() {
    vec2 projected_direction=(VIEW_MATRIX*vec4(direction,0.0)).xy;
    float roll=atan(projected_direction.y,projected_direction.x)-1.5707963268;
    VERTEX.xy=mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll)))*VERTEX.xy;
    MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
    float mask_value=texture(spark_texture,vec2(-UV.x,UV.y)).r;
    ALBEDO=particle_tint*material_intensity*3.0*mask_value;
    ALPHA=clamp(mask_value*3.0,0.0,1.0);
}
