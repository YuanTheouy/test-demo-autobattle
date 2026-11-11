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
uniform bool face_enabled;
uniform bool nose_enabled;
uniform bool secondary_enabled;
uniform vec4 face_planes[16];
uniform int face_count;
uniform vec4 nose_planes[8];
uniform int nose_count;

vec4 face_solid(vec3 origin, vec3 direction, bool nose) {
	float enter = -10000.0;
	float leave = 10000.0;
	vec3 normal = vec3(0.0);
	int count = nose ? nose_count : face_count;
	for (int i = 0; i < 16; i++) {
		if (i >= count) { break; }
		vec4 plane;
		if (nose) { plane = nose_planes[min(i, 7)]; } else { plane = face_planes[i]; }
		float denom = dot(plane.xyz, direction);
		float remaining = plane.w - dot(plane.xyz, origin);
		if (abs(denom) < 0.00001) {
			if (remaining < 0.0) { return vec4(0.0, 0.0, 0.0, -10000.0); }
		} else {
			float z = remaining / denom;
			if (denom > 0.0) {
				if (z < leave) { leave = z; normal = plane.xyz; }
			} else { enter = max(enter, z); }
		}
	}
	if (enter > leave || leave > 9999.0) { return vec4(0.0, 0.0, 0.0, -10000.0); }
	float light = clamp(dot(head_basis * normal, normalize(vec3(-0.3, 0.5, 0.8))), 0.0, 1.0);
	vec3 base = mix(vec3(0.74, 0.64, 0.51), vec3(0.84, 0.73, 0.59), max(normal.z, 0.0));
	return vec4(mix(base, vec3(1.0, 0.96, 0.85), light * 0.65), leave);
}

// Intersect a sphere clipped by a local-X slab. The largest camera Z wins.
vec4 solid(vec3 origin, vec3 direction, float low, float high, int region) {
	float b = dot(origin, direction);
	float discriminant = b * b - dot(origin, origin) + 1.0;
	if (discriminant < 0.0) { return vec4(0.0, 0.0, 0.0, -10000.0); }
	float root = sqrt(discriminant);
	float near_z = -b - root;
	float far_z = -b + root;
	float sphere_exit = far_z;
	vec3 clipped_normal = vec3(0.0);
	if (abs(direction.x) < 0.00001) {
		if (origin.x < low || origin.x > high) { return vec4(0.0, 0.0, 0.0, -10000.0); }
	} else {
		float z0 = (low - origin.x) / direction.x;
		float z1 = (high - origin.x) / direction.x;
		near_z = max(near_z, min(z0, z1));
		far_z = min(far_z, max(z0, z1));
		if (far_z < sphere_exit) { clipped_normal = vec3(sign(direction.x), 0.0, 0.0); }
	}
	if (region > 0) {
		vec3 n = region == 1 ? vec3(0.0, -1.0, 0.0) : vec3(0.0, 0.0, 1.0);
		float d = region == 1 ? -2.0 / 3.0 : 0.0;
		float denom = dot(n, direction);
		float remaining = d - dot(n, origin);
		if (abs(denom) < 0.00001) {
			if (remaining < 0.0) { return vec4(0.0, 0.0, 0.0, -10000.0); }
		} else {
			float z = remaining / denom;
			if (denom > 0.0) {
				if (z < far_z) { far_z = z; clipped_normal = n; }
			} else { near_z = max(near_z, z); }
		}
	}
	if (near_z > far_z) { return vec4(0.0, 0.0, 0.0, -10000.0); }
	bool is_cut = far_z < sphere_exit - 0.00001;
	vec3 normal = is_cut ? clipped_normal : normalize(origin + direction * far_z);
	vec3 base = is_cut ? vec3(0.600, 0.718, 0.627) : vec3(0.839, 0.776, 0.659);
	float light = clamp(dot(head_basis * normal, normalize(vec3(-0.3, 0.5, 0.8))), 0.0, 1.0);
	return vec4(mix(base, vec3(1.0, 0.973, 0.910), light * 0.55), far_z);
}

void fragment() {
	vec2 paper = (UV * canvas_size - center) / radius;
	mat3 inv = transpose(head_basis);
	vec3 origin = inv * vec3(paper.x, -paper.y, 0.0);
	vec3 direction = inv * vec3(0.0, 0.0, 1.0);
	float low = sliced ? -cut : -1.0;
	float high = sliced ? cut : 1.0;
	vec4 hit = solid(origin, direction, low, high, face_enabled ? 1 : 0);
	if (face_enabled) {
		vec4 back_skull = solid(origin, direction, low, high, 2);
		if (back_skull.a > hit.a) { hit = back_skull; }
		if (!secondary_enabled) {
			vec4 face = face_solid(origin, direction, false);
			if (face.a > hit.a) { hit = face; }
			if (nose_enabled) {
				vec4 nose = face_solid(origin, direction, true);
				if (nose.a > hit.a) { hit = nose; }
			}
		}
	}
	vec4 result = vec4(hit.rgb, hit.a > -9999.0 ? 1.0 : 0.0);
	if (sliced && caps) {
		vec4 left = solid(origin, direction, -1.0, -cut, 0);
		vec4 right = solid(origin, direction, cut, 1.0, 0);
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
