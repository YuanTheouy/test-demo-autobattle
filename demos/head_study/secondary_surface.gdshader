shader_type canvas_item;
render_mode unshaded;
uniform vec2 center;
uniform float radius;
uniform mat3 inverse_basis;
uniform float cut;
uniform bool sliced;
uniform bool caps;
uniform float cap_opacity;
varying vec2 paper_point;

void vertex() {
	paper_point=VERTEX;
}

// Clip the ray to the remaining skull. Face triangles are rasterized normally;
// this shader only rejects fragments genuinely behind the spherical skull.
float skull(vec3 o, vec3 d, int region) {
	float b = dot(o, d);
	float disc = b*b - dot(o,o) + 1.0;
	if (disc < 0.0) { return -10000.0; }
	float enter = -b - sqrt(disc);
	float leave = -b + sqrt(disc);
	for (int i=0; i<3; i++) {
		vec3 n;
		float limit;
		if (i==0) { n=vec3(1,0,0); limit=sliced ? cut : 1.0; }
		else if (i==1) { n=vec3(-1,0,0); limit=sliced ? cut : 1.0; }
		else { n=region==0 ? vec3(0,-1,0) : vec3(0,0,1); limit=region==0 ? -2.0/3.0 : 0.0; }
		float denom=dot(n,d);
		float remaining=limit-dot(n,o);
		if (abs(denom)<0.00001) {
			if (remaining<0.0) { return -10000.0; }
		} else if (denom>0.0) { leave=min(leave,remaining/denom); }
		else { enter=max(enter,remaining/denom); }
	}
	return enter<=leave ? leave : -10000.0;
}

void fragment() {
	vec2 paper=(paper_point-center)/radius;
	vec3 o=inverse_basis*vec3(paper.x,-paper.y,0);
	vec3 d=inverse_basis*vec3(0,0,1);
	float top=max(skull(o,d,0),skull(o,d,1));
	if (top > UV.x + 0.005) { discard; }
	// COLOR carries one flat, pre-lit color per planar patch.
	if (caps && sliced) {
		float b=dot(o,d);
		float disc=b*b-dot(o,o)+1.0;
		if (disc>=0.0) {
			float z=-b+sqrt(disc);
			vec3 p=o+d*z;
			if (abs(p.x)>cut && z>UV.x) {
				COLOR.rgb=mix(COLOR.rgb,vec3(0.89,0.85,0.77),cap_opacity);
			}
		}
	}
}
