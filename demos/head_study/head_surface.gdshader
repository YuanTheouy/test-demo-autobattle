shader_type canvas_item;
render_mode unshaded;

uniform vec2 canvas_size;
uniform vec2 center;
uniform float radius;
uniform mat3 head_basis;
uniform float cut;
uniform float cap_opacity;
uniform bool sliced;
uniform bool caps;

// Intersect a sphere clipped by a local-X slab. The largest camera Z wins.
vec4 solid(vec3 origin, vec3 direction, float low, float high) {
	float b = dot(origin, direction);
	float discriminant = b * b - dot(origin, origin) + 1.0;
	if (discriminant < 0.0) { return vec4(0.0, 0.0, 0.0, -10000.0); }
	float root = sqrt(discriminant);
	float near_z = -b - root;
	float far_z = -b + root;
	float sphere_exit = far_z;
	if (abs(direction.x) < 0.00001) {
		if (origin.x < low || origin.x > high) { return vec4(0.0, 0.0, 0.0, -10000.0); }
	} else {
		float z0 = (low - origin.x) / direction.x;
		float z1 = (high - origin.x) / direction.x;
		near_z = max(near_z, min(z0, z1));
		far_z = min(far_z, max(z0, z1));
	}
	if (near_z > far_z) { return vec4(0.0, 0.0, 0.0, -10000.0); }
	bool is_cut = far_z < sphere_exit - 0.00001;
	vec3 normal = is_cut ? vec3(sign(direction.x), 0.0, 0.0) : normalize(origin + direction * far_z);
	vec3 base = is_cut ? vec3(0.600, 0.718, 0.627) : vec3(0.839, 0.776, 0.659);
	float light = clamp(dot(head_basis * normal, normalize(vec3(-0.3, 0.5, 0.8))), 0.0, 1.0);
	return vec4(mix(base, vec3(1.0, 0.973, 0.910), light * 0.55), far_z);
}

void fragment() {
	vec2 paper = (UV * canvas_size - center) / radius;
	mat3 inv = transpose(head_basis);
	vec3 origin = inv * vec3(paper.x, -paper.y, 0.0);
	vec3 direction = inv * vec3(0.0, 0.0, 1.0);
	vec4 hit = solid(origin, direction, sliced ? -cut : -1.0, sliced ? cut : 1.0);
	vec4 result = vec4(hit.rgb, hit.a > -9999.0 ? 1.0 : 0.0);
	if (sliced && caps) {
		vec4 left = solid(origin, direction, -1.0, -cut);
		vec4 right = solid(origin, direction, cut, 1.0);
		vec4 cap = left.a > right.a ? left : right;
		if (cap.a > -9999.0 && cap.a >= hit.a) {
			if (hit.a > -9999.0) {
				result.rgb = mix(hit.rgb, cap.rgb, cap_opacity);
			} else {
				result = vec4(cap.rgb, cap_opacity);
			}
		}
	}
	COLOR = result;
}
