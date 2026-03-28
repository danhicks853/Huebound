shader_type canvas_item;

// Colorblind mode: 0.0 = Off, 1.0 = Protanopia, 2.0 = Deuteranopia, 3.0 = Tritanopia
uniform float mode = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 c = texture(screen_texture, SCREEN_UV);
	int m = int(mode);
	vec3 result = c.rgb;
	
	if (m > 0) {
		vec3 lin = c.rgb;
		vec3 sim = lin;
		
		if (m == 1) {
			// Protanopia (no red cones)
			sim = vec3(
				0.152286 * lin.r + 1.052583 * lin.g - 0.204868 * lin.b,
				0.114503 * lin.r + 0.786281 * lin.g + 0.099216 * lin.b,
				-0.003882 * lin.r - 0.048116 * lin.g + 1.051998 * lin.b
			);
		} else if (m == 2) {
			// Deuteranopia (no green cones)
			sim = vec3(
				0.367322 * lin.r + 0.860646 * lin.g - 0.227968 * lin.b,
				0.280085 * lin.r + 0.672501 * lin.g + 0.047413 * lin.b,
				-0.011820 * lin.r + 0.042940 * lin.g + 0.968881 * lin.b
			);
		} else if (m == 3) {
			// Tritanopia (no blue cones)
			sim = vec3(
				1.255528 * lin.r - 0.076749 * lin.g - 0.178779 * lin.b,
				-0.078411 * lin.r + 0.930809 * lin.g + 0.147602 * lin.b,
				0.004733 * lin.r + 0.691367 * lin.g + 0.303900 * lin.b
			);
		}
		
		// Daltonize: shift lost information into visible channels
		vec3 error = lin - sim;
		result = clamp(lin + vec3(0.0, 0.7 * error.r + error.g, 0.7 * error.r + error.b), 0.0, 1.0);
	}
	
	COLOR = vec4(result, c.a);
}
