extends Control
## La mappa d'Europa in 3D: una carta in rilievo (monti che si alzano dalla pergamena, mari animati)
## su un tavolo di mogano, con le pedine modellate (cannoni e corazzate, oppure carri e navi del modulo),
## i centri di rifornimento, le frecce degli ordini e le animazioni della risoluzione.
## Comandi: un dito o il tasto sinistro trascinano la mappa; due dita pizzicano per lo zoom e ruotano;
## tasto destro (o due dita in verticale) per inclinare; rotella per lo zoom.

const PX := 200.0            # pixel della mappa per unità 3D
const RILIEVO := 0.26        # altezza massima dei monti
const SCALA_PEDINA := 0.21

signal tocco(prov: int, su_unita: bool)

const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D carta : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D idmap : filter_nearest;
uniform sampler2D quota : filter_linear;
uniform sampler2D tavolozza : filter_nearest;
uniform float rilievo = 0.26;
uniform float tempo = 0.0;
void vertex() {
	float h = texture(quota, UV).r;
	VERTEX.y += h * rilievo;
	float e = 1.0 / 700.0;
	float hx = texture(quota, UV + vec2(e, 0.0)).r - texture(quota, UV - vec2(e, 0.0)).r;
	float hz = texture(quota, UV + vec2(0.0, e)).r - texture(quota, UV - vec2(0.0, e)).r;
	NORMAL = normalize(vec3(-hx * 2.2, 1.0, -hz * 2.2));
}
void fragment() {
	vec3 col = texture(carta, UV).rgb;
	ivec2 ts = textureSize(idmap, 0);
	vec4 idc = texelFetch(idmap, ivec2(UV * vec2(ts)), 0);
	int id = int(floor(idc.r * 255.0 + 0.5));
	bool terra = idc.g > 0.5;
	vec4 tinta = texelFetch(tavolozza, ivec2(id, 0), 0);
	vec4 luce = texelFetch(tavolozza, ivec2(id, 1), 0);
	if (terra) {
		col = mix(col, col * 0.42 + tinta.rgb * 0.62, tinta.a);
	} else {
		float o = sin(UV.x * 260.0 + tempo * 0.7 + sin(UV.y * 120.0 + tempo * 0.45) * 2.5) * sin(UV.y * 210.0 - tempo * 0.55);
		col += vec3(0.016, 0.02, 0.022) * o;
		float riva = 1.0 - clamp(idc.b * 255.0 / 28.0, 0.0, 1.0);
		col += vec3(0.05) * riva * (0.5 + 0.5 * sin(tempo * 1.1 - idc.b * 255.0 * 0.35));
	}
	col = mix(col, luce.rgb, luce.a * (0.48 + 0.16 * sin(tempo * 4.0)));
	ALBEDO = col;
	ROUGHNESS = terra ? 0.95 : 0.5;
	SPECULAR = terra ? 0.05 : 0.3;
}
"""

var st: DPState
var svc: SubViewportContainer
var vp: SubViewport
var cam: Camera3D
var mat_mappa: ShaderMaterial
var id_img: Image
var quota_img: Image
var tav_img: Image
var tav_tex: ImageTexture
var pedine: Node3D
var frecce: Node3D
var segni: Node3D
var centri_nodi := {}
var nodo_unita := {}          # provincia -> Node3D
var etichette: Array = []
var classiche := true
var luci := {}                # provincia -> Color (evidenziate)
var selezionata := -1
var anello: MeshInstance3D
var yaw := 0.0
var pitch := 1.02
var dist := 8.6
var target := Vector3.ZERO
var margine_destro := 0.0     # spazio coperto dai pannelli (pixel)
var margine_alto := 0.0
var margine_basso := 0.0
var _tw: Tween
var velocita := 1.0
var _touches := {}
var _pinch := {}
var _press := Vector2.ZERO
var _moved := false
var _t := 0.0
var _mesh := {}
var _mat := {}
var _font: Font
var _font_i: Font
var _nomi_lunghi := true
var _scala_pedine := 1.0


func setup() -> void:
	DPMap.ensure()
	UI.init_fonts()
	_font = UI.font_head
	_font_i = UI.font_ital
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	vp = SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.own_world_3d = true
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color("#0b0907")
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color("#efe6d2")
	en.ambient_light_energy = 0.5
	en.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = en
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 0.5
	sun.light_color = Color("#fff0d4")
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 26.0
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 38
	cam.near = 0.1
	cam.far = 80.0
	vp.add_child(cam)
	var mw := DPMap.larghezza / PX
	var mh := DPMap.altezza / PX
	# tavolo
	var table := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(40, 30)
	table.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_texture = UI.tex("res://assets/misc/tavolo.jpg")
	tmat.uv1_scale = Vector3(4, 3, 1)
	tmat.albedo_color = Color(0.5, 0.46, 0.44)
	tmat.roughness = 0.75
	table.material_override = tmat
	table.position.y = -0.06
	vp.add_child(table)
	# cornice d'ottone e legno
	var cornice := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(mw + 0.36, 0.07, mh + 0.36)
	cornice.mesh = cm
	cornice.position.y = -0.05
	cornice.material_override = _materiale(Color("#3a2416"), 0.6, 0.0)
	vp.add_child(cornice)
	var filo := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(mw + 0.07, 0.074, mh + 0.07)
	filo.mesh = fm
	filo.position.y = -0.048
	filo.material_override = _materiale(Color("#b08f45"), 0.35, 0.7)
	vp.add_child(filo)
	# la carta in rilievo
	var ci := _immagine("res://assets/mappa/base.jpg")
	ci.generate_mipmaps()
	id_img = _immagine("res://assets/mappa/id.png")
	quota_img = _immagine("res://assets/mappa/quota.png")
	tav_img = Image.create(256, 2, false, Image.FORMAT_RGBA8)
	tav_tex = ImageTexture.create_from_image(tav_img)
	var sh := Shader.new()
	sh.code = SHADER
	mat_mappa = ShaderMaterial.new()
	mat_mappa.shader = sh
	mat_mappa.set_shader_parameter("carta", ImageTexture.create_from_image(ci))
	mat_mappa.set_shader_parameter("idmap", ImageTexture.create_from_image(id_img))
	mat_mappa.set_shader_parameter("quota", ImageTexture.create_from_image(quota_img))
	mat_mappa.set_shader_parameter("tavolozza", tav_tex)
	mat_mappa.set_shader_parameter("rilievo", RILIEVO)
	var mappa := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(mw, mh)
	pm.subdivide_width = 340
	pm.subdivide_depth = 252
	mappa.mesh = pm
	mappa.material_override = mat_mappa
	mappa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mappa.extra_cull_margin = 1.0
	vp.add_child(mappa)
	segni = Node3D.new()
	vp.add_child(segni)
	pedine = Node3D.new()
	vp.add_child(pedine)
	frecce = Node3D.new()
	vp.add_child(frecce)
	_crea_etichette()
	_crea_centri()
	anello = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.13
	tor.outer_radius = 0.165
	tor.rings = 24
	tor.ring_segments = 8
	anello.mesh = tor
	var am := StandardMaterial3D.new()
	am.albedo_color = Color("#ffe07a")
	am.emission_enabled = true
	am.emission = Color("#ffd04a")
	am.emission_energy_multiplier = 1.6
	anello.material_override = am
	anello.scale = Vector3(1, 0.35, 1)
	anello.visible = false
	vp.add_child(anello)
	_cam()
	(func(): reset_view()).call_deferred()
	resized.connect(func(): reset_view())


## L'immagine di una texture del progetto (senza scheda grafica, nelle prove, la si legge dal file).
func _immagine(path: String) -> Image:
	var t: Texture2D = load(path)
	var img: Image = t.get_image() if t != null else null
	if img == null or img.is_empty():
		img = Image.new()
		img.load(path)
	if img.is_compressed():
		img.decompress()
	return img


func _materiale(col: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var k := "%s-%.2f-%.2f" % [col.to_html(), rough, metal]
	if not _mat.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_mat[k] = m
	return _mat[k]


func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3((p.x - DPMap.larghezza * 0.5) / PX, y, (p.y - DPMap.altezza * 0.5) / PX)


## Altezza del terreno in un punto della mappa.
func altezza(p: Vector2) -> float:
	var x := clampi(int(p.x), 0, quota_img.get_width() - 1)
	var y := clampi(int(p.y), 0, quota_img.get_height() - 1)
	return quota_img.get_pixel(x, y).r * RILIEVO


func pos_loc(l: int) -> Vector3:
	var p: Vector2 = DPMap.pos_pedina[l]
	return to3(p, altezza(p) + 0.004)


# ================================================================ etichette e centri

static func _spezza(n: String) -> String:
	if n.length() <= 11 or not n.contains(" "):
		return n
	var best := -1
	var bd := 99
	for i in n.length():
		if n[i] == " " and absi(i - n.length() / 2) < bd:
			bd = absi(i - n.length() / 2)
			best = i
	return n.substr(0, best) + "\n" + n.substr(best + 1)


func _crea_etichette() -> void:
	for i in DPMap.N_PROV:
		var l := Label3D.new()
		var mare := DPMap.tipo[i] == DPMap.MARE
		l.font = _font_i if mare else _font
		l.font_size = 40 if mare else 34
		l.pixel_size = 0.0026
		l.modulate = Color("#32566a") if mare else Color("#2a1b0e")
		l.outline_size = 8
		l.outline_modulate = Color(0.93, 0.89, 0.78, 0.75) if not mare else Color(0.82, 0.88, 0.9, 0.55)
		l.shaded = false
		l.double_sided = false
		l.no_depth_test = true
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		l.line_spacing = -8.0
		l.rotation.x = -PI / 2
		var p: Vector2 = DPMap.pos_etichetta[i]
		l.position = to3(p, altezza(p) + 0.012)
		l.set_meta("prov", i)
		l.render_priority = 2
		vp.add_child(l)
		etichette.append(l)
	_testi_etichette()


func _testi_etichette() -> void:
	for l in etichette:
		var i: int = l.get_meta("prov")
		l.text = _spezza(DPMap.nome[i]) if _nomi_lunghi else DPMap.sigla[i]


func _crea_centri() -> void:
	var bordo := CylinderMesh.new()
	bordo.top_radius = 0.054
	bordo.bottom_radius = 0.058
	bordo.height = 0.016
	bordo.radial_segments = 20
	var disco := CylinderMesh.new()
	disco.top_radius = 0.040
	disco.bottom_radius = 0.040
	disco.height = 0.024
	disco.radial_segments = 20
	for c in DPMap.centri:
		var n := Node3D.new()
		var p: Vector2 = DPMap.pos_stella[c]
		n.position = to3(p, altezza(p) + 0.008)
		var a := MeshInstance3D.new()
		a.mesh = bordo
		a.material_override = _materiale(Color("#2a1d10"), 0.5, 0.2)
		n.add_child(a)
		var b := MeshInstance3D.new()
		b.mesh = disco
		n.add_child(b)
		segni.add_child(n)
		centri_nodi[c] = b


# ================================================================ pedine

func _modello(nome: String) -> Mesh:
	if not _mesh.has(nome):
		_mesh[nome] = load("res://assets/modelli/%s.obj" % nome)
	return _mesh[nome]


func _crea_pedina(p: int, t: int) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var col: Color = DPMap.COLORI[p]
	var scuro := col.get_luminance() < 0.3
	if classiche:
		mi.mesh = _modello("cannone" if t == 0 else "corazzata")
		mi.scale = Vector3.ONE * (SCALA_PEDINA if t == 0 else SCALA_PEDINA * 1.25)
	else:
		mi.mesh = _modello("carro" if t == 0 else "nave")
		if t == 0:
			mi.scale = Vector3.ONE * 0.105
			mi.position.y = 0.036
		else:
			mi.scale = Vector3.ONE * 0.17
			mi.position.y = 0.018
			mi.rotation.y = PI / 2
	var m: Mesh = mi.mesh
	for s in m.get_surface_count():
		var nome := ""
		if m is ArrayMesh:
			nome = (m as ArrayMesh).surface_get_name(s)
		var mm: Material
		match nome:
			"metallo":
				mm = _materiale(Color("#8d9299") if scuro else Color("#34373c"), 0.4, 0.6)
			"legno":
				mm = _materiale(Color("#7a5632"), 0.8, 0.0)
			"chiaro":
				mm = _materiale(Color("#d9d6cc") if p != 5 else Color("#aab0b8"), 0.6, 0.1)
			_:
				mm = _materiale(col, 0.45, 0.15)
		mi.set_surface_override_material(s, mm)
	n.add_child(mi)
	n.rotation.y = -0.5 if t == 0 else 0.35
	if not classiche:
		# una base nel colore della potenza rende leggibili anche i modelli semplici
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.105
		cm.height = 0.012
		base.mesh = cm
		base.position.y = 0.006
		base.material_override = _materiale(col.darkened(0.25), 0.6, 0.1)
		n.add_child(base)
	return n


## Mostra una posizione: pedine, colori dei territori e dei centri.
func mostra(stato: DPState, ritirate: Array = []) -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	st = stato
	for ch in pedine.get_children():
		ch.queue_free()
	nodo_unita.clear()
	for i in DPMap.N_PROV:
		if st.up[i] < 0:
			continue
		var n := _crea_pedina(st.up[i], st.ut[i])
		n.position = pos_loc(st.ul[i])
		pedine.add_child(n)
		nodo_unita[i] = n
	for r in ritirate:
		var n := _crea_pedina(r["p"], r["t"])
		n.position = pos_loc(r["loc"]) + Vector3(-0.16, 0.02, 0.12)
		n.rotation.z = 0.35
		pedine.add_child(n)
		nodo_unita[1000 + int(r["prov"])] = n
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.10
		tor.outer_radius = 0.125
		ring.mesh = tor
		ring.scale = Vector3(1, 0.3, 1)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color("#ff4a3a")
		rm.emission_enabled = true
		rm.emission = Color("#ff3020")
		ring.material_override = rm
		ring.position = pos_loc(r["loc"]) + Vector3(-0.16, 0.012, 0.12)
		pedine.add_child(ring)
	for n in pedine.get_children():
		(n as Node3D).scale = Vector3.ONE * _scala_pedine
	_tavolozza()
	for c in DPMap.centri:
		var o := st.sc[c]
		var col: Color = DPMap.COLORI[o] if o >= 0 else Color("#d8c9a0")
		(centri_nodi[c] as MeshInstance3D).material_override = _materiale(col, 0.4, 0.3)
	seleziona(selezionata if st.up[selezionata] >= 0 else -1) if selezionata >= 0 else seleziona(-1)


func _tavolozza() -> void:
	tav_img.fill(Color(0, 0, 0, 0))
	if st != null:
		for i in DPMap.N_PROV:
			if DPMap.tipo[i] == DPMap.MARE:
				continue
			var c := Color(0, 0, 0, 0)
			if DPMap.centro[i] == 1:
				if st.sc[i] >= 0:
					c = Color(DPMap.COLORI[st.sc[i]], 0.6)
			elif st.up[i] >= 0:
				c = Color(DPMap.COLORI[st.up[i]], 0.42)
			elif DPMap.casa[i] >= 0 and st.n_centri(DPMap.casa[i]) > 0:
				c = Color(DPMap.COLORI[DPMap.casa[i]], 0.3)
			tav_img.set_pixel(i + 1, 0, c)
	for k in luci:
		tav_img.set_pixel(int(k) + 1, 1, luci[k])
	tav_tex.update(tav_img)


## Evidenzia delle province: {provincia: Color}.
func evidenzia(d: Dictionary) -> void:
	luci = d
	_tavolozza()


func seleziona(prov: int) -> void:
	selezionata = prov
	if prov >= 0 and st != null and st.up[prov] >= 0:
		anello.visible = true
		anello.position = pos_loc(st.ul[prov]) + Vector3(0, 0.012, 0)
	else:
		anello.visible = false


# ================================================================ frecce degli ordini

func pulisci_frecce() -> void:
	for ch in frecce.get_children():
		ch.queue_free()


## Disegna gli ordini: [{prov, o: [tipo, a, b], p, esito}] sulla posizione stato.
func disegna_ordini(stato: DPState, lista: Array) -> void:
	pulisci_frecce()
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in lista:
		var u: int = x["prov"]
		if stato.up[u] < 0:
			continue
		var o: Array = x["o"]
		var col: Color = DPMap.COLORI[x["p"]]
		if col.get_luminance() < 0.3:
			col = col.lightened(0.25)
		var fallito: bool = int(x.get("esito", 0)) != 0
		if fallito:
			col = col.lerp(Color("#7a1c12"), 0.55)
		var da := pos_loc(stato.ul[u])
		match int(o[0]):
			DPAdj.H:
				_anello_fermo(sf, da, col)
			DPAdj.M:
				var a := int(o[1])
				if a >= 0 and a < DPMap.N_LOC:
					var arr := pos_loc(a)
					_freccia(sf, da, arr, col, 0.027, false, fallito)
			DPAdj.S:
				var a := int(o[1])
				var b := int(o[2])
				if a >= 0 and a < DPMap.N_PROV and stato.up[a] >= 0:
					var pa := pos_loc(stato.ul[a])
					var fine := pa
					if b != a and b >= 0:
						fine = pa.lerp(pos_loc(b), 0.62)
					_tratteggio(sf, da, fine, col, 0.02, 0.07)
					_rombo(sf, fine + Vector3(0, 0.1, 0), col, 0.045)
			DPAdj.C:
				var a := int(o[1])
				var b := int(o[2])
				if a >= 0 and b >= 0 and a < DPMap.N_PROV and b < DPMap.N_PROV and stato.up[a] >= 0:
					var fine := pos_loc(stato.ul[a]).lerp(pos_loc(b), 0.5)
					_tratteggio(sf, da, fine, col, 0.016, 0.03)
	var m := sf.commit()
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.vertex_color_use_as_albedo = true
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frecce.add_child(mi)


func _arco(da: Vector3, a: Vector3, t: float) -> Vector3:
	var p := da.lerp(a, t)
	p.y = lerpf(da.y, a.y, t) + 0.1 + sin(t * PI) * (0.10 + 0.035 * da.distance_to(a))
	return p


func _quad(sf: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	sf.set_color(col)
	for v in [a, b, c, a, c, d]:
		sf.add_vertex(v)


func _freccia(sf: SurfaceTool, da: Vector3, a: Vector3, col: Color, w: float, _tr: bool, fallito: bool) -> void:
	var lung := Vector2(a.x - da.x, a.z - da.z).length()
	if lung < 0.05:
		return
	var t0 := clampf(0.13 / lung, 0.0, 0.4)
	var t1 := 1.0 - clampf(0.07 / lung, 0.0, 0.3)
	if fallito:
		t1 = lerpf(t0, t1, 0.72)
	var n := 12
	var bordo := Color(0.08, 0.05, 0.03)
	var testa := 0.16 / lung
	var prec := _arco(da, a, t0)
	for strato in 2:
		var ww := w + (0.012 if strato == 0 else 0.0)
		var cc := bordo if strato == 0 else col
		var dy := -0.004 if strato == 0 else 0.0
		prec = _arco(da, a, t0)
		var fine_fusto := t1 - testa * 0.8
		for i in range(1, n + 1):
			var t := lerpf(t0, fine_fusto, float(i) / n)
			var p := _arco(da, a, t)
			var dir := (p - prec)
			var lato := Vector3(dir.z, 0, -dir.x).normalized() * ww
			_quad(sf, prec - lato + Vector3(0, dy, 0), prec + lato + Vector3(0, dy, 0), p + lato + Vector3(0, dy, 0), p - lato + Vector3(0, dy, 0), cc)
			prec = p
		var punta := _arco(da, a, t1)
		var dir2 := punta - prec
		var lato2 := Vector3(dir2.z, 0, -dir2.x).normalized() * (ww * 2.6 + (0.006 if strato == 0 else 0.0))
		sf.set_color(cc)
		var ext := dir2.normalized() * (0.02 if strato == 0 else 0.0)
		sf.add_vertex(prec - lato2 + Vector3(0, dy, 0) - ext)
		sf.add_vertex(prec + lato2 + Vector3(0, dy, 0) - ext)
		sf.add_vertex(punta + Vector3(0, dy, 0) + ext)
	if fallito:
		# una croce rossa dove la mossa si è fermata
		var c := _arco(da, a, t1) + Vector3(0, 0.02, 0)
		var r := Color("#e0271a")
		for s in [1.0, -1.0]:
			var d1 := Vector3(0.06, 0, 0.06 * s)
			var l1 := Vector3(0.016 * s, 0, -0.016)
			_quad(sf, c - d1 - l1, c - d1 + l1, c + d1 + l1, c + d1 - l1, r)


func _tratteggio(sf: SurfaceTool, da: Vector3, a: Vector3, col: Color, w: float, passo: float) -> void:
	var lung := da.distance_to(a)
	if lung < 0.05:
		return
	var n := maxi(4, int(lung / passo))
	if n % 2 == 0:
		n += 1
	var bordo := Color(0.08, 0.05, 0.03)
	for i in n:
		if i % 2 == 1:
			continue
		var p0 := _arco_basso(da, a, lerpf(0.12, 1.0, float(i) / n))
		var p1 := _arco_basso(da, a, lerpf(0.12, 1.0, float(i + 1) / n))
		var dir := p1 - p0
		var lato := Vector3(dir.z, 0, -dir.x).normalized()
		_quad(sf, p0 - lato * (w + 0.008) - Vector3(0, 0.003, 0), p0 + lato * (w + 0.008) - Vector3(0, 0.003, 0),
			p1 + lato * (w + 0.008) - Vector3(0, 0.003, 0), p1 - lato * (w + 0.008) - Vector3(0, 0.003, 0), bordo)
		_quad(sf, p0 - lato * w, p0 + lato * w, p1 + lato * w, p1 - lato * w, col)


func _arco_basso(da: Vector3, a: Vector3, t: float) -> Vector3:
	var p := da.lerp(a, t)
	p.y = lerpf(da.y, a.y, t) + 0.1
	return p


func _rombo(sf: SurfaceTool, c: Vector3, col: Color, r: float) -> void:
	var bordo := Color(0.08, 0.05, 0.03)
	for strato in 2:
		var rr := r + (0.012 if strato == 0 else 0.0)
		var cc := bordo if strato == 0 else col
		var y := Vector3(0, -0.003 if strato == 0 else 0.0, 0)
		_quad(sf, c + Vector3(-rr, 0, 0) + y, c + Vector3(0, 0, -rr) + y, c + Vector3(rr, 0, 0) + y, c + Vector3(0, 0, rr) + y, cc)


func _anello_fermo(sf: SurfaceTool, c: Vector3, col: Color) -> void:
	var n := 16
	var r0 := 0.15
	var r1 := 0.175
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var y := Vector3(0, 0.02, 0)
		_quad(sf, c + Vector3(cos(a0) * r0, 0, sin(a0) * r0) + y, c + Vector3(cos(a0) * r1, 0, sin(a0) * r1) + y,
			c + Vector3(cos(a1) * r1, 0, sin(a1) * r1) + y, c + Vector3(cos(a1) * r0, 0, sin(a1) * r0) + y, col)


# ================================================================ animazione della risoluzione

## Anima una fase di movimento risolta: prima gli ordini, poi le pedine che si spostano o rimbalzano.
func anima_movimenti(voce: Dictionary) -> void:
	var prima := DPState.from_dict(voce["prima"])
	mostra(prima)
	var lista := []
	for u in voce["ordini"]:
		lista.append({"prov": u, "o": voce["ordini"][u], "p": prima.up[u], "esito": voce["esiti"][u]})
	disegna_ordini(prima, lista)
	await get_tree().create_timer(1.5 / velocita).timeout
	if not is_inside_tree():
		return
	var tw := create_tween().set_parallel(true)
	_tw = tw
	var qualcosa := false
	for u in voce["ordini"]:
		var o: Array = voce["ordini"][u]
		if int(o[0]) != DPAdj.M or not nodo_unita.has(u):
			continue
		var a := int(o[1])
		if a < 0 or a >= DPMap.N_LOC:
			continue
		var n: Node3D = nodo_unita[u]
		var da := n.position
		var arr := pos_loc(a)
		qualcosa = true
		if int(voce["esiti"][u]) == DPGame.E_OK:
			tw.tween_method(func(t: float): _salto(n, da, arr, t), 0.0, 1.0, 0.9 / velocita).set_trans(Tween.TRANS_SINE)
		else:
			var meta := da.lerp(arr, 0.3)
			tw.tween_method(func(t: float): _salto(n, da, meta, sin(t * PI)), 0.0, 1.0, 0.7 / velocita)
	for x in voce.get("sloggiate", []):
		var u: int = x[0]
		if nodo_unita.has(u):
			var n: Node3D = nodo_unita[u]
			qualcosa = true
			tw.tween_property(n, "rotation:z", 0.4, 0.5 / velocita).set_delay(0.5 / velocita)
			tw.tween_property(n, "position", n.position + Vector3(-0.16, 0.02, 0.12), 0.5 / velocita).set_delay(0.5 / velocita)
	if qualcosa and tw.is_valid():
		await tw.finished
	else:
		tw.kill()
	if is_inside_tree():
		await get_tree().create_timer(0.5 / velocita).timeout


func _salto(n: Node3D, da: Vector3, a: Vector3, t: float) -> void:
	if not is_instance_valid(n):
		return
	var p := da.lerp(a, t)
	p.y += sin(clampf(t, 0.0, 1.0) * PI) * 0.12
	n.position = p


# ================================================================ camera e tocchi

func _cam() -> void:
	if cam == null or not cam.is_inside_tree():
		return
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)
	var lunghi := dist < 6.2
	if lunghi != _nomi_lunghi or etichette.is_empty():
		_nomi_lunghi = lunghi
		_testi_etichette()
	var k := clampf(dist / 8.0, 0.8, 1.35) if not _nomi_lunghi else clampf(dist / 5.2, 0.62, 1.1)
	for l in etichette:
		(l as Label3D).pixel_size = 0.0026 * k
		(l as Label3D).rotation.y = yaw
	# da lontano le pedine si ingrandiscono un poco, per restare leggibili
	_scala_pedine = clampf(dist / 6.5, 1.0, 1.55)
	if pedine != null:
		for n in pedine.get_children():
			(n as Node3D).scale = Vector3.ONE * _scala_pedine


func reset_view() -> void:
	yaw = 0.0
	pitch = 1.02
	# lo spazio libero dai pannelli: la mappa intera deve starci, centrata lì
	var fw := maxf(240.0, size.x - margine_destro)
	var fh := maxf(240.0, size.y - margine_alto - margine_basso)
	var k := 2.0 * tan(deg_to_rad(cam.fov * 0.5))
	var mw := DPMap.larghezza / PX + 0.25
	var mh := DPMap.altezza / PX * sin(pitch) + 0.55
	dist = clampf(maxf(mw * size.y / (k * fw), mh * size.y / (k * fh)), 4.0, 15.0)
	var c := Vector2(fw * 0.5, margine_alto + fh * 0.5) - size * 0.5
	var upp := k * dist / maxf(1.0, size.y)
	target = Vector3(-c.x * upp, 0, -c.y * upp / sin(pitch) + 0.5)
	_cam()


func _process(dt: float) -> void:
	_t += dt
	if mat_mappa != null:
		mat_mappa.set_shader_parameter("tempo", _t)
	if anello != null and anello.visible:
		var s := 1.0 + sin(_t * 4.0) * 0.08
		anello.scale = Vector3(s, 0.35, s)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
			_press = ev.position
			if _touches.size() == 1:
				_moved = false
			else:
				_moved = true
		else:
			var tap: bool = _touches.size() == 1 and not _moved
			_touches.erase(ev.index)
			_pinch = {}
			if tap:
				_click(ev.position)
		accept_event()
		return
	if ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if ev.position.distance_to(_press) > 12:
			_moved = true
		if _touches.size() == 1:
			if _moved:
				_pan(ev.relative)
		elif _touches.size() >= 2:
			var ks := _touches.keys()
			var a: Vector2 = _touches[ks[0]]
			var b: Vector2 = _touches[ks[1]]
			var d := a.distance_to(b)
			var ang := (b - a).angle()
			var mid := (a + b) * 0.5
			if not _pinch.is_empty():
				dist = clampf(dist * _pinch["d"] / maxf(1.0, d), 1.8, 15.0)
				yaw -= wrapf(ang - _pinch["ang"], -PI, PI)
				pitch = clampf(pitch + (mid.y - _pinch["mid"].y) * 0.004, 0.35, 1.52)
				_cam()
			_pinch = {"d": d, "ang": ang, "mid": mid}
		accept_event()
		return
	if ev is InputEventMagnifyGesture:
		dist = clampf(dist / ev.factor, 1.8, 15.0)
		_cam()
		accept_event()
		return
	if ev is InputEventPanGesture:
		_pan(-ev.delta * 10.0)
		accept_event()
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			dist = clampf(dist * 0.9, 1.8, 15.0)
			_cam()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			dist = clampf(dist / 0.9, 1.8, 15.0)
			_cam()
		elif ev.pressed:
			_press = ev.position
			_moved = false
		elif ev.button_index == MOUSE_BUTTON_LEFT and not _moved and _touches.is_empty():
			_click(ev.position)
		accept_event()
	elif ev is InputEventMouseMotion and ev.button_mask != 0 and _touches.is_empty():
		if ev.position.distance_to(_press) > 6:
			_moved = true
		if ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= ev.relative.x * 0.006
			pitch = clampf(pitch + ev.relative.y * 0.004, 0.35, 1.52)
			_cam()
		elif _moved:
			_pan(ev.relative)
		accept_event()


func _pan(rel: Vector2) -> void:
	var k := dist * 0.00095
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	target += (-right * rel.x + fwd * rel.y) * k
	target.x = clampf(target.x, -5.0, 5.0)
	target.z = clampf(target.z, -3.8, 3.8)
	_cam()


## Punto della mappa (in pixel) sotto un punto dello schermo.
func punto_mappa(s: Vector2) -> Vector2:
	var sc := s * Vector2(vp.size) / size
	var o := cam.project_ray_origin(sc)
	var dir := cam.project_ray_normal(sc)
	if absf(dir.y) < 0.0001:
		return Vector2(-9999, -9999)
	# si parte dal piano e si corregge qualche volta con l'altezza del terreno trovato
	var h := 0.0
	var m := Vector2.ZERO
	for k in 5:
		var t := (h - o.y) / dir.y
		var hit := o + dir * t
		m = Vector2(hit.x * PX + DPMap.larghezza * 0.5, hit.z * PX + DPMap.altezza * 0.5)
		h = altezza(m) + 0.004
	return m


func provincia_in(m: Vector2) -> int:
	var sx := float(id_img.get_width()) / DPMap.larghezza
	var x := int(m.x * sx)
	var y := int(m.y * sx)
	if x < 0 or y < 0 or x >= id_img.get_width() or y >= id_img.get_height():
		return -1
	return int(round(id_img.get_pixel(x, y).r * 255.0)) - 1


func _click(s: Vector2) -> void:
	var m := punto_mappa(s)
	# prima le pedine: quella più vicina al tocco
	var best := -1
	var bd := 34.0
	if st != null:
		for i in DPMap.N_PROV:
			if st.up[i] >= 0:
				var d := m.distance_to(DPMap.pos_pedina[st.ul[i]])
				if d < bd:
					bd = d
					best = i
	if best >= 0:
		tocco.emit(best, true)
		return
	var p := provincia_in(m)
	if p >= 0:
		tocco.emit(p, false)


## Punto dello schermo di una località (per i fumetti 2D sopra la mappa).
func schermo_loc(l: int) -> Vector2:
	var p := cam.unproject_position(pos_loc(l))
	return p * size / Vector2(vp.size)
