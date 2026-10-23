"""
Builds the household rig parts (pulleys, reels, rulers, crayons, spoons, tins, sacks, presents,
books, baubles, door handles, cookie leftovers) in Blender and exports rig_parts.glb.
Run headless:  blender -b -P build_rig_parts.py -- <out_dir> [preview_dir]

Shared parts library: scripts/mech/part_models.gd loads these pieces for the rigs, the checks and
the player build tool (scripts/build/), so every placed part looks the same everywhere.
Everything is authored at REAL size in metres and in GODOT axes (x right, y up, z toward the
viewer); G() converts to Blender's Z-up (Godot -Z = Blender +Y, the glTF exporter undoes it).
Each piece is a top-level empty named after the piece, origin at the physics body's centre.
Chunky Hello Neighbor charm: bevels, subdivision, a little wonk. Flat base colours only;
Godot swaps them for the toon shader (material names starting Wood/Metal/Glass/Wrap/Rope keep
their special looks).
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/models"
PREVIEW = argv[1] if len(argv) > 1 else ""
os.makedirs(OUT, exist_ok=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)


def G(x, y, z):
    return Vector((x, -z, y))


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MATS = {}


def mat(name, rgb, rough=0.6, metal=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[srgb2lin(c) for c in rgb], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m


COLL = bpy.data.collections.new("RigParts")
bpy.context.scene.collection.children.link(COLL)


def own(o):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    COLL.objects.link(o)
    return o


def finish(o, m, sub=0, bevel=0.0, seg=2):
    own(o)
    if bevel > 0:
        bv = o.modifiers.new("bev", "BEVEL")
        bv.width = bevel
        bv.segments = seg
        bv.limit_method = "ANGLE"
    if sub:
        md = o.modifiers.new("sub", "SUBSURF")
        md.levels = sub
        md.render_levels = sub
    o.data.materials.clear()
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


AX = {"x": (0, math.radians(90), 0), "y": (0, 0, 0), "z": (math.radians(90), 0, 0)}


def cyl(m, c, r, h, axis="y", verts=32, r2=None, bevel=0.0, sub=0):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=G(*c), vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=G(*c), vertices=verts)
    o = bpy.context.active_object
    o.rotation_euler = AX[axis]
    if axis == "x" and r2 is not None:
        o.rotation_euler = (0, math.radians(90), 0)
    return finish(o, m, sub, bevel)


def rbox(m, c, size, bevel=0.002, sub=0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=G(*c))
    o = bpy.context.active_object
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler = (math.radians(rot[0]), math.radians(-rot[2]), math.radians(rot[1]))
    bv = o.modifiers.new("bev", "BEVEL")
    bv.width = bevel
    bv.segments = 3
    return finish(o, m, sub)


def ball(m, c, r, scale=(1, 1, 1), seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=G(*c), segments=seg, ring_count=seg // 2)
    o = bpy.context.active_object
    o.scale = (scale[0], scale[2], scale[1])
    return finish(o, m)


def torus(m, c, R, r, axis="y", scale=(1, 1, 1), rot=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=G(*c), major_segments=40, minor_segments=12)
    o = bpy.context.active_object
    o.rotation_euler = rot if rot is not None else AX[axis]
    o.scale = (scale[0], scale[2], scale[1])
    return finish(o, m)


def tube(m, pts, r, radii=None, closed=False, res=12):
    cu = bpy.data.curves.new("t", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 3
    cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for i, (bp, p) in enumerate(zip(sp.bezier_points, pts)):
        bp.co = G(*p)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        if radii:
            bp.radius = radii[i]
    sp.use_cyclic_u = closed
    o = bpy.data.objects.new("t", cu)
    COLL.objects.link(o)
    o.data.materials.append(m)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.view_layer.objects.active
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def cut(o, cutter):
    md = o.modifiers.new("cut", "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.object = cutter
    md.solver = "EXACT"
    bpy.context.view_layer.objects.active = o
    for mm in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mm.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return o


def piece(name, parts):
    e = bpy.data.objects.new(name, None)
    COLL.objects.link(e)
    bpy.context.view_layer.update()
    for i, p in enumerate(parts):
        p.name = "%s_%02d" % (name, i)
        mw = p.matrix_world.copy()
        p.parent = e
        p.matrix_world = mw
    return e


# ---- materials ----------------------------------------------------------------------------------
STEEL = mat("MetalSteel", (0.62, 0.64, 0.68), 0.35, 1.0)
DARKSTEEL = mat("MetalDark", (0.26, 0.27, 0.3), 0.4, 1.0)
BRASS = mat("MetalBrass", (0.8, 0.62, 0.3), 0.3, 1.0)
ZINC = mat("MetalTin", (0.72, 0.74, 0.76), 0.3, 1.0)
WHEEL = mat("PulleyNylon", (0.16, 0.3, 0.55))
WOOD = mat("WoodRuler", (0.86, 0.7, 0.45))
WOODD = mat("WoodSpoon", (0.78, 0.58, 0.36))
WOODR = mat("WoodReel", (0.9, 0.78, 0.58))
INK = mat("Ink", (0.08, 0.07, 0.07))
RED = mat("CrayonRed", (0.85, 0.14, 0.12))
PAPER = mat("CrayonPaper", (0.93, 0.3, 0.22))
THREAD = mat("Thread", (0.75, 0.12, 0.2))
YELLOW = mat("PencilYellow", (0.95, 0.75, 0.15))
PINK = mat("Eraser", (0.95, 0.55, 0.6))
LABEL = mat("TinLabel", (0.15, 0.45, 0.3))
LABEL2 = mat("TinLabelBand", (0.95, 0.85, 0.5))
SACK = mat("Hessian", (0.55, 0.42, 0.26))
STRING = mat("Twine", (0.82, 0.72, 0.5))
COAL = mat("Coal", (0.08, 0.08, 0.09), 0.3)
WRAP = mat("WrapRed", (0.72, 0.1, 0.14))
RIBBON = mat("RibbonGold", (0.95, 0.8, 0.28), 0.3)
COVER = mat("BookCover", (0.16, 0.3, 0.6))
PAGES = mat("BookPages", (0.96, 0.93, 0.84))
GILT = mat("BookGilt", (0.9, 0.75, 0.3), 0.3)
MARKER = mat("BookRibbon", (0.75, 0.1, 0.12))
GLASSR = mat("GlassRed", (0.82, 0.08, 0.12), 0.1)
GOLD = mat("MetalGold", (0.85, 0.68, 0.3), 0.25, 1.0)
MARBLE = [mat("GlassBlue", (0.2, 0.5, 0.95), 0.1), mat("GlassGreen", (0.25, 0.8, 0.4), 0.1),
          mat("GlassAmber", (0.95, 0.6, 0.15), 0.1), mat("GlassWhite", (0.92, 0.94, 0.98), 0.1), GLASSR]
COOKIE = mat("Cookie", (0.78, 0.52, 0.26))
CHOC = mat("Choc", (0.28, 0.15, 0.08))
PLATE = mat("Plate", (0.95, 0.95, 0.92), 0.3)
PLATERIM = mat("PlateRim", (0.2, 0.4, 0.75), 0.3)


# ---- pulley: a sewing-box pulley wheel in a bent steel bracket with a screw hook ------------------
def pulley():
    r = 0.02  # groove radius (the rope radius the physics uses)
    wheel = cyl(WHEEL, (0, 0, 0), r + 0.006, 0.012, "z", 48, bevel=0.0015)
    g = torus(WHEEL, (0, 0, 0), r + 0.0062, 0.0042, "z")
    cut(wheel, g)
    for k in range(4):  # lightening holes
        a = k * math.pi / 2 + math.pi / 4
        h = cyl(WHEEL, (math.cos(a) * 0.012, math.sin(a) * 0.012, 0), 0.0035, 0.03, "z", 20)
        cut(wheel, h)
    hub = cyl(DARKSTEEL, (0, 0, 0), 0.006, 0.016, "z", 24, bevel=0.001)
    axle = cyl(STEEL, (0, 0, 0), 0.0024, 0.026, "z", 16)
    nuts = [cyl(STEEL, (0, 0, s * 0.0135), 0.0042, 0.003, "z", 6, bevel=0.0005) for s in (1, -1)]
    plates = [rbox(STEEL, (0, 0.016, s * 0.0105), (0.016, 0.05, 0.0018), 0.0008) for s in (1, -1)]
    for p in plates:
        p.modifiers.new("sub", "SUBSURF").levels = 1
    bridge = tube(STEEL, [(0, 0.04, 0.0105), (0, 0.046, 0.006), (0, 0.047, 0), (0, 0.046, -0.006), (0, 0.04, -0.0105)], 0.0022)
    eye = torus(STEEL, (0, 0.053, 0), 0.005, 0.0013, "x")
    hook = tube(BRASS, [(0, 0.056, 0), (0, 0.066, 0), (0.004, 0.074, 0), (0.009, 0.072, 0), (0.01, 0.066, 0)], 0.0016)
    piece("Pulley", [wheel, hub, axle, *nuts, *plates, bridge, eye, hook])


# ---- cotton reel winch: a wooden reel of red thread on a pencil axle, paperclip crank ------------
def reel():
    parts = []
    for s in (1, -1):
        parts.append(cyl(WOODR, (0, 0, s * 0.0175), 0.019, 0.005, "z", 40, bevel=0.0012))
    parts.append(cyl(WOODR, (0, 0, 0), 0.0098, 0.032, "z", 32))
    parts.append(cyl(THREAD, (0, 0, 0), 0.0119, 0.0295, "z", 40, bevel=0.0006))
    for k in range(9):
        parts.append(torus(THREAD, (0, 0, -0.0135 + k * 0.0034), 0.0119, 0.0011, "z"))
    tail = tube(THREAD, [(0.0119, 0.0, 0.005), (0.016, -0.01, 0.006), (0.014, -0.02, 0.004)], 0.0006)
    parts.append(tail)
    for s in (1, -1):
        parts.append(cyl(INK, (0, 0, s * 0.0202), 0.0042, 0.0006, "z", 24))
    pencil = cyl(YELLOW, (0, 0, -0.005), 0.0036, 0.07, "z", 6, bevel=0.0004)
    tipw = cyl(WOODR, (0, 0, -0.0445), 0.0036, 0.012, "z", 6)
    tipw.rotation_euler = (math.radians(-90), 0, 0)
    parts += [pencil]
    piece("CottonReel", parts)
    # bent paperclip crank: double wire, rounded bends; the elf's hands go on the eraser grip
    w = 0.0008
    path_a = [(0, 0.0015, 0.024), (0.02, 0.0015, 0.024), (0.045, 0.0015, 0.024), (0.05, 0.0015, 0.027), (0.05, 0.0015, 0.04)]
    path_b = [(0, -0.0015, 0.024), (0.02, -0.0015, 0.024), (0.045, -0.0015, 0.024), (0.05, -0.0015, 0.027), (0.05, -0.0015, 0.04)]
    a = tube(STEEL, path_a, w)
    b = tube(STEEL, path_b, w)
    loop = torus(STEEL, (0, 0, 0.024), 0.0036, w, "z")
    grip = cyl(PINK, (0.05, 0, 0.034), 0.0045, 0.012, "z", 20, bevel=0.0012)
    piece("ReelCrank", [a, b, loop, grip])


# ---- ruler: a 30 cm wooden school ruler, bevelled, with cm / mm ticks and a steel edge -------------
def ruler():
    L, W, T = 0.30, 0.03, 0.0035
    parts = [rbox(WOOD, (0, 0, 0), (L, T, W), 0.0009)]
    parts.append(rbox(STEEL, (0, T * 0.15, -W * 0.5 + 0.0012), (L - 0.004, T * 0.5, 0.0022), 0.0004))
    for i in range(0, 61):
        x = -0.145 + i * 0.005 * 0.97
        ln = 0.009 if i % 2 == 0 else 0.005
        if i % 10 == 0:
            ln = 0.012
        parts.append(rbox(INK, (x, T * 0.5 + 0.00012, -W * 0.5 + 0.0028 + ln * 0.5), (0.0006, 0.0003, ln), 0.0001))
    for i in range(0, 31, 5):  # chunky number blocks every 5 cm
        x = -0.145 + i * 0.01 * 0.97
        parts.append(rbox(INK, (x + 0.002, T * 0.5 + 0.00012, 0.006), (0.0035, 0.0003, 0.005), 0.0002))
    parts.append(cyl(INK, (0.12, T * 0.5, 0.004), 0.0028, 0.0008, "y", 24))  # hanging hole
    piece("Ruler", parts)


# ---- crayon: a jumbo wax crayon with its paper wrapper (lies along x) -------------------------------
def crayon():
    r, L = 0.006, 0.1
    body = cyl(RED, (-0.004, 0, 0), r, L - 0.022, "x", 32, bevel=0.0012)
    cone = cyl(RED, (L * 0.5 - 0.013, 0, 0), r, 0.016, "x", 32, r2=0.0022)
    tip = ball(RED, (L * 0.5 - 0.0045, 0, 0), 0.0023)
    wrap = cyl(PAPER, (-0.008, 0, 0), r + 0.00035, 0.068, "x", 32)
    bands = [torus(INK, (-0.008 + s * 0.026, 0, 0), r + 0.0004, 0.0007, "x") for s in (1, -1)]
    zig = [rbox(INK, (-0.008 + k * 0.006, r + 0.0003, 0), (0.0022, 0.0005, 0.0018), 0.0002, rot=(0, 0, 25 if k % 2 else -25)) for k in range(-3, 4)]
    piece("Crayon", [body, cone, tip, wrap, *bands, *zig])


# ---- wooden spoon (a long cooking spoon) used as a catapult arm: bowl at +x --------------------------
def spoon():
    L = 0.5
    handle = tube(WOODD, [(-0.25, 0, 0), (-0.05, 0.0005, 0), (0.12, 0.001, 0), (0.165, 0.002, 0)], 0.0075, radii=[0.85, 1.0, 1.05, 1.25])
    handle.scale = (1, 1.6, 0.75)  # flattened (Blender y = Godot z width, z = Godot y thickness)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(0, 0, 0), segments=32, ring_count=16)
    bowl = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(bowl.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > 0.05], context="VERTS")
    bm.to_mesh(bowl.data)
    bm.free()
    bowl.scale = (0.05, 0.03, 0.016)
    bowl.location = G(0.205, 0.008, 0)
    finish(bowl, WOODD)
    sol = bowl.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.08
    sol.offset = 1
    bowl.modifiers.new("sub", "SUBSURF").levels = 1
    piece("Spoon", [handle, bowl])


# ---- counterweights ---------------------------------------------------------------------------------
def tin():
    r, h = 0.05, 0.12  # 1.5 kg of marbles (1.5 g/cm3 packed glass)
    parts = [cyl(ZINC, (0, 0, 0), r, h, "y", 48, bevel=0.0015)]
    for k in (-0.035, 0.0, 0.035):
        parts.append(torus(ZINC, (0, k - 0.01, 0), r + 0.0002, 0.0012, "y"))
    parts.append(cyl(LABEL, (0, -0.012, 0), r + 0.0006, 0.07, "y", 48))
    parts.append(cyl(LABEL2, (0, -0.012, 0), r + 0.0009, 0.016, "y", 48))
    parts.append(torus(ZINC, (0, h * 0.5, 0), r - 0.001, 0.0022, "y"))
    parts.append(torus(ZINC, (0, -h * 0.5, 0), r - 0.001, 0.0018, "y"))
    inner = cyl(mat("TinInside", (0.35, 0.36, 0.38), 0.4, 1.0), (0, h * 0.5 - 0.012, 0), r - 0.003, 0.0015, "y", 40)
    parts.append(inner)
    import random
    rnd = random.Random(5)
    for k in range(26):  # a heap of marbles showing over the rim
        a = rnd.random() * math.tau
        d = math.sqrt(rnd.random()) * (r - 0.012)
        y = h * 0.5 - 0.006 + (1 - d / r) * 0.008 + rnd.random() * 0.002
        parts.append(ball(MARBLE[k % len(MARBLE)], (math.cos(a) * d, y, math.sin(a) * d), 0.0075, seg=16))
    piece("MarbleTin", parts)


def sack():
    # a small hessian coal sack (1 kg of coal ~ 1.25 L): 0.11 wide, 0.13 tall body, tied neck
    bpy.ops.object.metaball_add(type="BALL", location=(0, 0, 0))
    mb = bpy.context.active_object
    mbd = mb.data
    mbd.resolution = 0.006
    mbd.render_resolution = 0.006
    mbd.elements.clear()
    for c, s in [((0, -0.015, 0), (0.05, 0.045, 0.045)), ((0, 0.02, 0), (0.042, 0.03, 0.04)), ((0, 0.05, 0), (0.016, 0.012, 0.016))]:
        el = mbd.elements.new()
        el.type = "ELLIPSOID"
        el.co = G(*c)
        el.radius = 1.0 / 0.575
        el.size_x, el.size_y, el.size_z = s[0], s[2], s[1]
    mbd.materials.append(SACK)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = mb
    mb.select_set(True)
    bpy.ops.object.convert(target="MESH")
    body = own(bpy.context.view_layer.objects.active)
    for p in body.data.polygons:
        p.use_smooth = True
    tie = torus(STRING, (0, 0.046, 0), 0.0115, 0.0018, "y")
    knot = tube(STRING, [(0.011, 0.046, 0), (0.02, 0.05, 0.004), (0.026, 0.044, 0.008)], 0.0014)
    knot2 = tube(STRING, [(0.011, 0.046, 0), (0.019, 0.04, -0.004), (0.024, 0.033, -0.002)], 0.0014)
    ruff = cyl(SACK, (0, 0.062, 0), 0.016, 0.014, "y", 12, r2=0.024)
    lumps = [ball(COAL, (0.004 * k - 0.006, 0.07, 0.003 * ((k * 7) % 3 - 1)), 0.0065, (1.1, 0.8, 0.9), 12) for k in range(4)]
    patch = rbox(mat("HessianDark", (0.42, 0.31, 0.18)), (0.0, -0.01, 0.0485), (0.034, 0.03, 0.002), 0.001)
    piece("CoalSack", [body, tie, knot, knot2, ruff, *lumps, patch])


# ---- present, book, bauble -----------------------------------------------------------------------------
def present():
    sx, sy, sz = 0.2, 0.16, 0.2
    box = rbox(WRAP, (0, -0.012, 0), (sx - 0.004, sy - 0.024, sz - 0.004), 0.003)
    lid = rbox(WRAP, (0, sy * 0.5 - 0.014, 0), (sx, 0.028, sz), 0.003)
    dots = []
    import random
    rnd = random.Random(3)
    star = mat("WrapStar", (0.97, 0.92, 0.75))
    for face in range(4):
        for k in range(7):
            u = rnd.uniform(-0.08, 0.08)
            v = rnd.uniform(-0.06, 0.04)
            n = [(1, 0), (-1, 0), (0, 1), (0, -1)][face]
            c = (n[0] * (sx * 0.5 - 0.0018) + (u if n[0] == 0 else 0), v, n[1] * (sz * 0.5 - 0.0018) + (u if n[1] == 0 else 0))
            d = ball(star, c, 0.0065, (0.35 if n[0] else 1, 1, 0.35 if n[1] else 1), 12)
            dots.append(d)
    rib = [rbox(RIBBON, (0, 0, 0), (0.028, sy + 0.003, sz + 0.003), 0.0008), rbox(RIBBON, (0, 0, 0), (sx + 0.003, sy + 0.003, 0.028), 0.0008)]
    bow = [torus(RIBBON, (s * 0.022, sy * 0.5 + 0.012, 0), 0.02, 0.0045, rot=(0, math.radians(s * 55), 0), scale=(1, 0.75, 0.55)) for s in (1, -1)]
    knot = ball(RIBBON, (0, sy * 0.5 + 0.006, 0), 0.009, (1.2, 0.8, 1.0), 16)
    tails = [tube(RIBBON, [(0, sy * 0.5 + 0.004, 0), (s * 0.02, sy * 0.5 + 0.003, 0.03), (s * 0.03, sy * 0.5 + 0.002, 0.06)], 0.004, radii=[1, 1, 0.7]) for s in (1, -1)]
    for t in tails:
        t.scale = (1, 1, 0.3)
    tag = rbox(mat("GiftTag", (0.98, 0.96, 0.88)), (0.07, sy * 0.5 + 0.0015, 0.05), (0.03, 0.001, 0.02), 0.0006, rot=(0, 25, 0))
    piece("Present", [box, lid, *dots, *rib, *bow, knot, *tails, tag])


def book():
    sx, sy, sz = 0.15, 0.025, 0.21
    cov = [rbox(COVER, (0.002, s * (sy * 0.5 - 0.00125), 0), (sx - 0.004, 0.0025, sz), 0.0008) for s in (1, -1)]
    spine = cyl(COVER, (-sx * 0.5 + 0.004, 0, 0), sy * 0.5, sz, "z", 32)
    spine.scale = (0.45, 1, 1)
    pages = rbox(PAGES, (0.004, 0, 0), (sx - 0.01, sy - 0.0055, sz - 0.008), 0.0012)
    lines = [rbox(mat("PageEdge", (0.85, 0.82, 0.72)), (sx * 0.5 - 0.0009, -0.008 + k * 0.004, 0), (0.0004, 0.0006, sz - 0.01), 0.0001) for k in range(5)]
    gilt = [rbox(GILT, (-sx * 0.5 + 0.0005, 0, s * 0.06), (0.002, sy * 0.6, 0.004), 0.0005) for s in (1, -1)]
    title = rbox(GILT, (0.01, sy * 0.5 + 0.0002, -0.04), (0.08, 0.0006, 0.022), 0.0004)
    motif = cyl(GILT, (0.01, sy * 0.5 + 0.0002, 0.03), 0.018, 0.0006, "y", 6)
    mark = tube(MARKER, [(0.02, 0.0, sz * 0.5 - 0.004), (0.022, -0.002, sz * 0.5 + 0.02), (0.018, -0.006, sz * 0.5 + 0.035)], 0.0022)
    mark.scale = (1, 1, 0.25)
    piece("Book", [*cov, spine, pages, *lines, *gilt, title, motif, mark])


def bauble():
    r = 0.03
    glass = ball(GLASSR, (0, 0, 0), r, seg=32)
    band = torus(GOLD, (0, 0, 0), r * 0.995, 0.0012, "y")
    cap = cyl(GOLD, (0, r + 0.002, 0), 0.0075, 0.008, "y", 24, bevel=0.0006)
    ribs = [torus(GOLD, (0, r - 0.001 + k * 0.0025, 0), 0.0076, 0.0005, "y") for k in range(3)]
    loop = torus(GOLD, (0, r + 0.0095, 0), 0.0035, 0.0007, "z")
    shine = ball(mat("GlassShine", (1.0, 0.9, 0.88), 0.05), (-0.011, 0.016, 0.02), 0.006, (1, 1.4, 0.35), 12)
    piece("Bauble", [glass, band, cap, *ribs, loop, shine])


# ---- door handles (test rigs show them; the house doors carry their own modelled hardware) ------------
def handles():
    rose = cyl(BRASS, (0, 0, 0.004), 0.026, 0.008, "z", 40, bevel=0.0018)
    neck = cyl(BRASS, (0, 0, 0.018), 0.0085, 0.024, "z", 24, bevel=0.001)
    arm = tube(BRASS, [(0, 0, 0.03), (-0.025, 0, 0.034), (-0.08, -0.001, 0.034), (-0.118, -0.006, 0.03)], 0.0075, radii=[1.1, 0.95, 0.9, 1.1])
    arm.scale = (1, 0.7, 1.0)  # Blender z = Godot y: flatten the bar
    tipb = ball(BRASS, (-0.118, -0.006, 0.03), 0.0085, (1.1, 0.8, 1))
    screws = [cyl(DARKSTEEL, (0, s * 0.017, 0.0082), 0.0022, 0.001, "z", 12) for s in (1, -1)]
    piece("LeverHandle", [rose, neck, arm, tipb, *screws])
    rose2 = cyl(BRASS, (0, 0, 0.004), 0.026, 0.008, "z", 40, bevel=0.0018)
    neck2 = cyl(BRASS, (0, 0, 0.02), 0.009, 0.028, "z", 24, r2=0.0075, bevel=0.001)
    knob = ball(BRASS, (0, 0, 0.042), 0.028, (1, 1, 0.72), 32)
    collar = torus(BRASS, (0, 0, 0.026), 0.0085, 0.0018, "z")
    piece("KnobHandle", [rose2, neck2, knob, collar])


# ---- cookie leftovers --------------------------------------------------------------------------------------
def leftovers():
    import random
    rnd = random.Random(11)
    plate = cyl(PLATE, (0, 0.005, 0), 0.105, 0.008, "y", 48, r2=0.075, bevel=0.002)
    well = cyl(PLATE, (0, 0.0095, 0), 0.072, 0.0015, "y", 48)
    rim = torus(PLATERIM, (0, 0.0088, 0), 0.096, 0.0012, "y")
    ck = cyl(COOKIE, (0.025, 0.014, -0.01), 0.033, 0.008, "y", 32, bevel=0.0025)
    for (bx, bz, br) in [(0.05, -0.03, 0.017), (0.056, 0.0, 0.014)]:
        cut(ck, cyl(COOKIE, (bx, 0.014, bz), br, 0.03, "y", 24))
    chips = [ball(CHOC, (0.025 + rnd.uniform(-0.022, 0.012), 0.018, -0.01 + rnd.uniform(-0.02, 0.02)), 0.0035, (1, 0.6, 1), 10) for _ in range(6)]
    crumbs = []
    for k in range(22):
        a = rnd.random() * math.tau
        d = rnd.uniform(0.01, 0.085)
        crumbs.append(ball(COOKIE if k % 4 else CHOC, (math.cos(a) * d - 0.01, 0.0115, math.sin(a) * d), rnd.uniform(0.0018, 0.0042), (1, 0.6, 1.2), 8))
    piece("CookiePlate", [plate, well, rim, ck, *chips, *crumbs])
    glass = cyl(mat("GlassClear", (0.85, 0.92, 1.0), 0.05), (0, 0.06, 0), 0.034, 0.12, "y", 40, r2=0.03)
    film = cyl(mat("MilkFilm", (0.98, 0.98, 0.95), 0.3), (0, 0.004, 0), 0.0305, 0.006, "y", 40)
    ring = torus(mat("MilkFilm", (0.98, 0.98, 0.95)), (0, 0.085, 0), 0.0325, 0.0009, "y")
    drip = tube(mat("MilkFilm", (0.98, 0.98, 0.95)), [(0.0325, 0.085, 0.0), (0.033, 0.06, 0.004), (0.033, 0.045, 0.003)], 0.0012)
    piece("MilkGlassEmpty", [glass, film, ring, drip])


pulley(); reel(); ruler(); crayon(); spoon(); tin(); sack(); present(); book(); bauble(); handles(); leftovers()

bpy.ops.object.select_all(action="DESELECT")
for o in COLL.all_objects:
    o.select_set(True)
path = os.path.join(OUT, "rig_parts.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                          export_yup=True, export_materials="EXPORT")
print("exported", path)
