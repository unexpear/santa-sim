"""
Builds the Santa Sim character models in Blender (4.2 LTS) and exports GLB files.
Run headless:  blender -b -P build_models.py -- <out_dir> [preview_dir]

Conventions: Blender Z-up, models face +Y (the glTF exporter turns this into Godot's -Z forward).
The sleigh and Santa share the sleigh's local origin so Santa drops straight into the seat.
Sleigh dimensions are matched to the gameplay collision in scripts/sleigh.gd:
runners at x = +/-0.7 with their bottom at z = -0.66, tub about 1.5 m wide.
All shapes are smooth: metaballs (organic bodies), bevelled bezier curves (runners, scrolls,
antlers, reins) and subdivision surfaces. Only flat base colours are used; Godot swaps them
for the toon shader.
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/models"
PREVIEW = argv[1] if len(argv) > 1 else ""
os.makedirs(OUT, exist_ok=True)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    bpy.data.collections.remove(c)

K = 0.575  # metaball surface radius / element radius (stiffness 2, threshold 0.6)


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MATS = {}


def mat(name, rgb, emit=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = (*[srgb2lin(c) for c in rgb], 1.0)
    b.inputs["Base Color"].default_value = lin
    b.inputs["Roughness"].default_value = 0.6
    if emit > 0:
        b.inputs["Emission Color"].default_value = lin
        b.inputs["Emission Strength"].default_value = emit
    MATS[name] = m
    return m


COL = {}


def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    COL["cur"] = c
    return c


def link(obj):
    COL["cur"].objects.link(obj)
    return obj


def set_mat(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)


def smooth(obj, sub=0):
    if obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True
    if sub:
        md = obj.modifiers.new("sub", "SUBSURF")
        md.levels = sub
        md.render_levels = sub
    return obj


def to_mesh(obj):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.view_layer.objects.active
    smooth(o)
    return o


# ---- metaballs --------------------------------------------------------------------------------

def meta(name, m, elems, res=0.018):
    """elems: ('e', center, (a,b,c), rot_euler_deg) ellipsoid | ('c', p, q, R) capsule | ('b', c, R) ball"""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = 0.6
    obj = link(bpy.data.objects.new(name, mb))
    for e in elems:
        el = mb.elements.new()
        if e[0] == "b":
            el.type = "BALL"
            el.co = e[1]
            el.radius = e[2] / K
        elif e[0] == "e":
            el.type = "ELLIPSOID"
            el.co = e[1]
            el.radius = 1.0 / K
            el.size_x, el.size_y, el.size_z = e[2]
            if len(e) > 3:
                r = e[3]
                el.rotation = Matrix.Rotation(math.radians(r[2]), 4, "Z").to_quaternion() @ \
                    Matrix.Rotation(math.radians(r[1]), 4, "Y").to_quaternion() @ \
                    Matrix.Rotation(math.radians(r[0]), 4, "X").to_quaternion()
        else:
            p, q, R = Vector(e[1]), Vector(e[2]), e[3]
            el.type = "CAPSULE"
            el.co = (p + q) / 2
            el.radius = R / K
            el.size_x = max((q - p).length / 2, 0.001)
            el.rotation = Vector((1, 0, 0)).rotation_difference((q - p).normalized())
    mb.materials.append(m)
    o = to_mesh(obj)
    o.name = name
    return o


# ---- primitives (always smooth / subdivided, never raw boxes) ---------------------------------

def sphere(name, m, c, r, scale=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=c, segments=24, ring_count=12)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.rotation_euler = [math.radians(a) for a in rot]
    move_to_cur(o)
    set_mat(o, m)
    return smooth(o)


def rbox(name, m, c, size, rot=(0, 0, 0), bevel=0.05, sub=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.rotation_euler = [math.radians(a) for a in rot]
    move_to_cur(o)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bv = o.modifiers.new("bev", "BEVEL")
    bv.width = bevel
    bv.segments = 3
    set_mat(o, m)
    return smooth(o, sub)


def torus(name, m, c, R, r, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=c,
                                     major_segments=32, minor_segments=12)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = [math.radians(a) for a in rot]
    o.scale = scale
    move_to_cur(o)
    set_mat(o, m)
    return smooth(o)


def move_to_cur(o):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    COL["cur"].objects.link(o)


# ---- curves -----------------------------------------------------------------------------------

def tube(name, m, pts, r, closed=False, taper_end=None, radii=None):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 4
    cu.resolution_u = 14
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    if taper_end is not None:
        n = len(sp.bezier_points)
        for i, bp in enumerate(sp.bezier_points):
            bp.radius = 1.0 + (taper_end - 1.0) * i / max(n - 1, 1)
    if radii is not None:
        for bp, rr in zip(sp.bezier_points, radii):
            bp.radius = rr
    sp.use_cyclic_u = closed
    o = link(bpy.data.objects.new(name, cu))
    o.data.materials.append(m)
    return to_mesh(o)


def side_slab(name, m, pts_yz, x_center, half_thick, bevel=0.03):
    """Filled, rounded 2D outline drawn in the YZ plane and extruded along X."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    cu.extrude = half_thick
    cu.bevel_depth = bevel
    cu.bevel_resolution = 3
    cu.resolution_u = 16
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts_yz) - 1)
    for bp, (y, z) in zip(sp.bezier_points, pts_yz):
        bp.co = (y, z, 0)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    sp.use_cyclic_u = True
    o = link(bpy.data.objects.new(name, cu))
    o.matrix_world = Matrix(((0, 0, 1, x_center), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    o.data.materials.append(m)
    return to_mesh(o)


def spiral(cy, cz, x, r0, r1, turns, start_deg=90, n=40, direction=1):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = math.radians(start_deg) + direction * t * turns * math.tau
        r = r0 + (r1 - r0) * t
        pts.append((x, cy + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def pivot_group(name, loc, children):
    """Empty used as an animation pivot (exported as a glTF node); children keep their world placement."""
    bpy.context.view_layer.update()
    e = link(bpy.data.objects.new(name, None))
    e.location = loc
    bpy.context.view_layer.update()
    for c in children:
        mw = c.matrix_world.copy()
        c.parent = e
        c.matrix_world = mw
    return e


# ---- export -----------------------------------------------------------------------------------

def export(coll, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.all_objects:
        o.select_set(True)
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    print("exported", path)


# =================================================================================================
# INTERIORS: furniture + the stealth elf  (furniture.glb, elf.glb)
# Furniture convention: every piece is one top-level empty named after the piece (Couch, Bed, ...)
# with its origin on the floor at the centre of its footprint; the front (where you sit / the doors)
# faces +Y here, which is Godot's -Z. Godot builds collision from each piece's bounds.
# Shapes are chunky, bevelled and subdivided, with a little crooked Hello Neighbor wonk.
# Material names matter: Godot swaps "Brick" for a brick pattern and keeps "*Glow*" emissive.
# Run only these:  SANTA_ONLY=interiors,elf blender -b -P build_models.py -- <out_dir> [preview_dir]
# =================================================================================================
ONLY = os.environ.get("SANTA_ONLY", "")


def cyl(name, m, c, r, h, rot=(0, 0, 0), verts=24, r2=None, sub=0, bevel=0.0):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=c, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=c, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = [math.radians(a) for a in rot]
    move_to_cur(o)
    if bevel > 0:
        bv = o.modifiers.new("bev", "BEVEL")
        bv.width = bevel
        bv.segments = 2
    set_mat(o, m)
    return smooth(o, sub)


def wonk(o, taper=0.0, bend=0.0, axis="Z"):
    """Crooked Hello Neighbor feel: a little taper and bend (applied on export)."""
    if taper:
        md = o.modifiers.new("taper", "SIMPLE_DEFORM")
        md.deform_method = "TAPER"
        md.factor = taper
        md.deform_axis = axis
    if bend:
        md = o.modifiers.new("bend", "SIMPLE_DEFORM")
        md.deform_method = "BEND"
        md.angle = math.radians(bend)
        md.deform_axis = axis
    return o


def piece(name, parts, x_off=0.0):
    e = link(bpy.data.objects.new(name, None))
    bpy.context.view_layer.update()
    for p in parts:
        mw = p.matrix_world.copy()
        p.parent = e
        p.matrix_world = mw
    return e


def build_interiors():
    import random
    rnd = random.Random(7)
    furn = collection("Furniture")
    WOOD = mat("Wood", (0.62, 0.36, 0.18))
    WOOD_D = mat("WoodDark", (0.38, 0.2, 0.1))
    WOOD_L = mat("WoodLight", (0.86, 0.66, 0.42))
    TEAL = mat("CouchTeal", (0.1, 0.55, 0.55))
    TEAL_D = mat("CouchTealDark", (0.06, 0.4, 0.42))
    MUSTARD = mat("Mustard", (0.92, 0.66, 0.12))
    CREAM = mat("Cream", (0.96, 0.9, 0.78))
    WHITE = mat("White", (0.95, 0.95, 0.92))
    BLACK = mat("Black", (0.06, 0.06, 0.08))
    METAL = mat("Metal", (0.62, 0.64, 0.68))
    BRICK = mat("Brick", (0.72, 0.3, 0.2))
    SOOT = mat("Soot", (0.05, 0.04, 0.04))
    STONE = mat("Stone", (0.55, 0.52, 0.5))
    PINK = mat("BlanketPink", (0.95, 0.42, 0.6))
    BLUE = mat("BlanketBlue", (0.22, 0.45, 0.9))
    PURPLE = mat("BlanketPurple", (0.5, 0.25, 0.75))
    GREEN = mat("TreeGreen", (0.12, 0.5, 0.25))
    GREEN_D = mat("TreeGreenDark", (0.07, 0.36, 0.18))
    REDF = mat("FabricRed", (0.85, 0.12, 0.1))
    GOLD = mat("Gold", (1.0, 0.78, 0.2))
    LEAF = mat("Leaf", (0.2, 0.62, 0.28))
    POT = mat("Terracotta", (0.8, 0.42, 0.25))
    SCREEN = mat("ScreenGlow", (0.25, 0.45, 0.75), emit=0.6)
    SHADE = mat("LampShadeGlow", (1.0, 0.82, 0.55), emit=1.2)
    BULB_COLS = [(1, 0.2, 0.15), (0.2, 1, 0.3), (0.3, 0.5, 1), (1, 0.8, 0.2), (1, 0.4, 0.9)]
    BULBS = [mat("TreeLightGlow%d" % i, c, emit=4.0) for i, c in enumerate(BULB_COLS)]
    BAUBLES = [mat("Bauble%d" % i, c) for i, c in enumerate([(0.9, 0.1, 0.12), (1, 0.75, 0.15), (0.2, 0.4, 0.95), (0.85, 0.3, 0.85)])]
    BOOKS = [mat("Book%d" % i, c) for i, c in enumerate([(0.8, 0.15, 0.15), (0.15, 0.45, 0.8), (0.95, 0.75, 0.2), (0.2, 0.6, 0.3), (0.6, 0.3, 0.7), (0.95, 0.5, 0.2), (0.9, 0.9, 0.85)])]

    # ---- living room ----
    # Clearances under furniture (the crouched elf, 0.11 m, crawls under; see scripts/elf_size.gd):
    # couches/armchairs 0.14 m, side tables 0.16, TV unit 0.16, wardrobe 0.15, beds 0.24.
    # Parts named "Leg*"/"Post*" become thin leg colliders in Godot; the rest collides as one raised box.
    CL = 0.04  # couch lift: base bottom 0.10 -> 0.14
    p = []
    p.append(wonk(rbox("CouchBase", TEAL_D, (0, 0, 0.25 + CL), (2.1, 0.9, 0.3), bevel=0.08, sub=1), taper=0.04))
    for i in range(3):
        p.append(rbox("Seat%d" % i, TEAL, (-0.68 + i * 0.68, 0.06, 0.47 + CL), (0.66, 0.76, 0.16), rot=(rnd.uniform(-2, 2), 0, rnd.uniform(-3, 3)), bevel=0.07, sub=2))
        p.append(rbox("Back%d" % i, TEAL, (-0.68 + i * 0.68, -0.33, 0.78 + CL), (0.64, 0.22, 0.5), rot=(-12 + rnd.uniform(-4, 4), 0, rnd.uniform(-4, 4)), bevel=0.09, sub=2))
    for s in (-1, 1):
        p.append(rbox("Arm%d" % s, TEAL_D, (s * 1.08, 0.0, 0.5 + CL), (0.26, 0.92, 0.42), rot=(0, s * 6, 0), bevel=0.11, sub=2))
        for yy in (-0.35, 0.35):
            p.append(cyl("Leg", WOOD_D, (s * 0.95, yy, 0.075), 0.04, 0.15, r2=0.03))
    p.append(rbox("Cushion", MUSTARD, (0.7, 0.05, 0.68 + CL), (0.36, 0.14, 0.36), rot=(70, 20, 15), bevel=0.1, sub=2))
    piece("Couch", p)

    p = []
    p.append(wonk(rbox("ChairBase", MUSTARD, (0, 0, 0.25 + CL), (0.95, 0.88, 0.3), bevel=0.08, sub=1), taper=0.06))
    p.append(rbox("Seat", MUSTARD, (0, 0.06, 0.47 + CL), (0.66, 0.72, 0.16), bevel=0.07, sub=2))
    p.append(wonk(rbox("Back", MUSTARD, (0, -0.33, 0.85 + CL), (0.8, 0.22, 0.75), rot=(-10, 0, 3), bevel=0.1, sub=2), taper=-0.2))
    for s in (-1, 1):
        p.append(rbox("Arm", MUSTARD, (s * 0.44, 0.02, 0.52 + CL), (0.2, 0.86, 0.36), bevel=0.09, sub=2))
        for yy in (-0.32, 0.32):
            p.append(cyl("Leg", WOOD_D, (s * 0.38, yy, 0.075), 0.035, 0.15, r2=0.025))
    piece("Armchair", p)

    p = [wonk(rbox("Top", WOOD, (0, 0, 0.4), (1.2, 0.65, 0.07), rot=(0, 1.5, 0), bevel=0.03, sub=1), bend=6, axis="X"),
         rbox("Shelf", WOOD_D, (0, 0, 0.2), (1.05, 0.5, 0.04), bevel=0.015, sub=1)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(cyl("Leg", WOOD_D, (sx * 0.52, sy * 0.26, 0.2), 0.035, 0.4, rot=(sy * 4, sx * -4, 0), r2=0.025))
    for i in range(3):
        p.append(rbox("Mag%d" % i, [REDF, BLUE, GOLD][i], (0.25 + i * 0.03, 0.05, 0.45 + i * 0.012), (0.3, 0.22, 0.012), rot=(0, 0, rnd.uniform(-25, 25)), bevel=0.003, sub=0))
    piece("CoffeeTable", p)

    TL = 0.14  # TV unit stands on legs: cabinet bottom 0.16
    p = [wonk(rbox("Cabinet", WOOD_L, (0, 0, 0.28 + TL), (1.6, 0.45, 0.52), bevel=0.04, sub=1), taper=0.05),
         rbox("DrawerL", WOOD, (-0.4, 0.22, 0.28 + TL), (0.7, 0.04, 0.38), bevel=0.02, sub=1),
         rbox("DrawerR", WOOD, (0.4, 0.22, 0.28 + TL), (0.7, 0.04, 0.38), bevel=0.02, sub=1)]
    for s in (-1, 1):
        p.append(sphere("Knob", GOLD, (s * 0.4, 0.26, 0.3 + TL), 0.03))
        for yy in (-1, 1):
            p.append(cyl("Leg", WOOD_D, (s * 0.72, yy * 0.17, 0.09), 0.03, 0.18, r2=0.022, verts=12))
    piece("TVUnit", p)

    p = [rbox("Body", BLACK, (0, 0, 0.42), (1.15, 0.12, 0.7), rot=(0, rnd.uniform(-2, 2), 0), bevel=0.03, sub=1),
         rbox("Screen", SCREEN, (0, 0.05, 0.44), (1.02, 0.04, 0.58), bevel=0.01, sub=0),
         cyl("Neck", BLACK, (0, 0, 0.06), 0.05, 0.12), rbox("Foot", BLACK, (0, 0, 0.01), (0.4, 0.22, 0.03), bevel=0.01, sub=0)]
    piece("TV", p)

    p = [wonk(rbox("Frame", WOOD, (0, 0, 0.95), (1.0, 0.36, 1.9), bevel=0.03, sub=1), taper=0.06, bend=3, axis="Z")]
    p.append(rbox("Backboard", WOOD_D, (0, -0.15, 0.95), (0.9, 0.04, 1.8), bevel=0.01, sub=0))
    for k in range(5):
        z = 0.08 + k * 0.42
        p.append(rbox("Shelf%d" % k, WOOD_L, (0, 0.02, z), (0.92, 0.32, 0.04), bevel=0.01, sub=0))
        if k == 4:
            break
        bx = -0.4
        while bx < 0.36:
            w = rnd.uniform(0.04, 0.08)
            h = rnd.uniform(0.22, 0.34)
            lean = rnd.uniform(-8, 8) if rnd.random() < 0.3 else 0
            p.append(rbox("Book", BOOKS[rnd.randint(0, 6)], (bx + w / 2, 0.02, z + 0.02 + h / 2), (w, 0.24, h), rot=(0, lean, 0), bevel=0.006, sub=0))
            bx += w + 0.008
    piece("Bookshelf", p)

    # ---- dining + kitchen ----
    p = [wonk(rbox("Top", WOOD, (0, 0, 0.74), (1.6, 0.9, 0.07), bevel=0.03, sub=1), bend=4, axis="X")]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(wonk(cyl("Leg", WOOD_D, (sx * 0.7, sy * 0.36, 0.37), 0.045, 0.74, r2=0.03, verts=12), bend=5))
    p.append(rbox("Runner", REDF, (0, 0, 0.78), (1.2, 0.28, 0.01), bevel=0.002, sub=0))
    piece("DiningTable", p)

    p = [rbox("Seat", WOOD, (0, 0, 0.45), (0.45, 0.44, 0.05), bevel=0.02, sub=1),
         rbox("Pad", REDF, (0, 0.01, 0.49), (0.38, 0.36, 0.04), bevel=0.02, sub=1)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(cyl("Leg", WOOD_D, (sx * 0.19, sy * 0.19, 0.22), 0.025, 0.45, r2=0.02, verts=10))
        p.append(cyl("Post", WOOD_D, (sx * 0.19, -0.2, 0.72), 0.025, 0.55, verts=10))
    for k in range(3):
        p.append(rbox("Slat%d" % k, WOOD, (0, -0.2, 0.62 + k * 0.14), (0.38, 0.03, 0.06), rot=(0, rnd.uniform(-4, 4), 0), bevel=0.01, sub=0))
    piece("DiningChair", p)

    def counter(name, sink=False):
        q = [rbox("Cab", WHITE, (0, 0, 0.45), (1.0, 0.62, 0.84), bevel=0.02, sub=1),
             rbox("Plinth", BLACK, (0, 0.02, 0.04), (0.96, 0.56, 0.08), bevel=0.01, sub=0),
             wonk(rbox("Bench", WOOD_L, (0, 0.02, 0.91), (1.04, 0.68, 0.06), bevel=0.015, sub=1), bend=2, axis="X")]
        for s in (-1, 1):
            q.append(rbox("Door", MUSTARD if not sink else BLUE, (s * 0.24, 0.31, 0.47), (0.46, 0.03, 0.7), bevel=0.02, sub=1))
            q.append(cyl("Handle", METAL, (s * 0.06, 0.34, 0.66), 0.012, 0.16))
        if sink:
            q.append(rbox("Sink", METAL, (0, 0.04, 0.9), (0.55, 0.4, 0.06), bevel=0.02, sub=1))
            q.append(tube("Tap", METAL, [(0, -0.22, 0.94), (0, -0.22, 1.2), (0, -0.05, 1.18), (0, 0.0, 1.08)], 0.02))
        else:
            q.append(cyl("Kettle", REDF, (0.25, -0.05, 1.03), 0.08, 0.18, r2=0.06, sub=1))
            q.append(rbox("Board", WOOD, (-0.2, 0.0, 0.95), (0.35, 0.25, 0.02), rot=(0, 0, 10), bevel=0.01, sub=0))
        return piece(name, q)

    counter("KitchenCounter")
    counter("KitchenSink", sink=True)

    p = [wonk(rbox("Body", WHITE, (0, 0, 0.93), (0.8, 0.74, 1.86), bevel=0.08, sub=2), taper=0.05, bend=3),
         rbox("Split", METAL, (0, 0.37, 1.3), (0.74, 0.01, 0.015), bevel=0.003, sub=0),
         cyl("HandleT", METAL, (-0.3, 0.4, 1.55), 0.018, 0.35), cyl("HandleB", METAL, (-0.3, 0.4, 0.95), 0.018, 0.45)]
    for i in range(5):
        p.append(rbox("Magnet%d" % i, [REDF, GOLD, BLUE, LEAF, PINK][i], (rnd.uniform(-0.1, 0.25), 0.38, rnd.uniform(1.0, 1.7)), (0.08, 0.02, 0.08), rot=(0, rnd.uniform(-20, 20), 0), bevel=0.01, sub=0))
    p.append(rbox("Drawing", WHITE, (0.1, 0.38, 1.5), (0.22, 0.005, 0.28), rot=(0, 6, 0), bevel=0.0, sub=0))
    piece("Fridge", p)

    p = [rbox("Body", WHITE, (0, 0, 0.45), (0.76, 0.64, 0.86), bevel=0.03, sub=1),
         rbox("Top", BLACK, (0, 0.0, 0.9), (0.76, 0.64, 0.03), bevel=0.01, sub=0),
         rbox("OvenDoor", BLACK, (0, 0.32, 0.4), (0.62, 0.03, 0.45), bevel=0.02, sub=1),
         cyl("OvenHandle", METAL, (0, 0.36, 0.67), 0.015, 0.5, rot=(0, 90, 0)),
         rbox("Backsplash", WHITE, (0, -0.3, 1.0), (0.76, 0.06, 0.2), bevel=0.02, sub=1)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(torus("Burner", METAL, (sx * 0.18, sy * 0.14 + 0.02, 0.925), 0.09, 0.015))
    for k in range(4):
        p.append(cyl("Knob", BLACK, (-0.24 + k * 0.16, -0.26, 1.05), 0.03, 0.04, rot=(90, 0, 0)))
    piece("Stove", p)

    # ---- bedrooms ----
    BL = 0.17  # bed lift: frame bottom 0.07 -> 0.24 on four legs (room for an elf + the classic clutter)
    def bed(name, w, blanket, kid=False):
        q = [rbox("Frame", WOOD, (0, 0, 0.18 + BL), (w + 0.1, 2.1, 0.22), bevel=0.04, sub=1),
             wonk(rbox("Headboard", WOOD_D if not kid else BLUE, (0, -1.06, 0.6 + BL), (w + 0.2, 0.1, 1.0 if not kid else 0.8), bevel=0.06, sub=2), taper=-0.08),
             rbox("Footboard", WOOD_D if not kid else BLUE, (0, 1.06, 0.36 + BL), (w + 0.2, 0.08, 0.5), bevel=0.05, sub=2),
             rbox("Mattress", WHITE, (0, 0, 0.38 + BL), (w, 2.0, 0.2), bevel=0.06, sub=2)]
        for sx in (-1, 1):
            for sy in (-1, 1):
                q.append(cyl("Leg", WOOD_D, (sx * (w / 2 + 0.02), sy * 1.03, 0.13), 0.045, 0.26, r2=0.035, verts=12))
        bl = rbox("Blanket", blanket, (0, 0.28, 0.5 + BL), (w + 0.12, 1.45, 0.08), bevel=0.04, sub=2)
        wonk(bl, bend=-14, axis="X")
        q.append(bl)
        q.append(rbox("Fold", WHITE, (0, -0.42, 0.53 + BL), (w + 0.08, 0.22, 0.07), rot=(4, 0, 0), bevel=0.035, sub=2))
        n = 1 if kid else 2
        for i in range(n):
            px = 0 if n == 1 else (-w / 4 + i * w / 2)
            q.append(rbox("Pillow%d" % i, CREAM, (px, -0.8, 0.55 + BL), (w / n - 0.1, 0.38, 0.14), rot=(rnd.uniform(-8, 8), 0, rnd.uniform(-8, 8)), bevel=0.07, sub=2))
        if kid:
            q.append(sphere("TeddyBody", WOOD_L, (0.15, -0.55, 0.62 + BL), 0.09, scale=(1, 0.8, 1.15)))
            q.append(sphere("TeddyHead", WOOD_L, (0.15, -0.58, 0.76 + BL), 0.07))
            for s in (-1, 1):
                q.append(sphere("TeddyEar", WOOD, (0.15 + s * 0.05, -0.58, 0.82 + BL), 0.025))
        return piece(name, q)

    bed("BedDouble", 1.6, PURPLE)
    bed("BedKid", 1.0, BLUE, kid=True)

    p = [wonk(rbox("Body", WOOD, (0, 0, 1.075), (1.2, 0.6, 1.85), bevel=0.04, sub=1), taper=0.07, bend=-4),
         rbox("Crown", WOOD_D, (0, 0, 2.02), (1.3, 0.66, 0.08), bevel=0.02, sub=0)]
    for s in (-1, 1):
        p.append(rbox("Door", WOOD_L, (s * 0.29, 0.3, 1.1), (0.55, 0.03, 1.7), rot=(0, s * 1.5, 0), bevel=0.02, sub=1))
        p.append(sphere("Knob", GOLD, (s * 0.07, 0.33, 1.1), 0.03))
        for yy in (-1, 1):
            p.append(cyl("Leg", WOOD_D, (s * 0.52, yy * 0.24, 0.085), 0.035, 0.17, r2=0.025, verts=12))
    piece("Wardrobe", p)

    SL = 0.13  # side table body bottom 0.16 (top 0.66)
    p = [wonk(rbox("Body", WOOD_L, (0, 0, 0.28 + SL), (0.5, 0.42, 0.5), bevel=0.03, sub=1), taper=0.1),
         rbox("Drawer", WOOD, (0, 0.21, 0.36 + SL), (0.42, 0.03, 0.16), bevel=0.01, sub=0), sphere("Knob", GOLD, (0, 0.24, 0.36 + SL), 0.025)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(cyl("Leg", WOOD_D, (sx * 0.2, sy * 0.16, 0.09), 0.025, 0.18, r2=0.018, verts=12))
    piece("SideTable", p)

    p = [sphere("Base", MUSTARD, (0, 0, 0.12), 0.11, scale=(1, 1, 1.15)), cyl("Stem", METAL, (0, 0, 0.3), 0.012, 0.2),
         wonk(cyl("Shade", SHADE, (0, 0, 0.45), 0.17, 0.2, r2=0.1, verts=24, rot=(0, 5, 0)), bend=6)]
    piece("Lamp", p)

    p = [cyl("Base", BLACK, (0, 0, 0.02), 0.18, 0.04), cyl("Pole", METAL, (0, 0, 0.6), 0.02, 1.1),
         cyl("Shade", SHADE, (0, 0, 1.25), 0.26, 0.32, r2=0.16, rot=(0, 4, 0))]
    piece("FloorLamp", p)

    # ---- rugs (thin, soft, with a border) ----
    p = [cyl("Rug", REDF, (0, 0, 0.01), 1.1, 0.02, verts=40, bevel=0.008),
         cyl("Inner", GOLD, (0, 0, 0.018), 0.85, 0.02, verts=40), cyl("Core", BLUE, (0, 0, 0.024), 0.5, 0.02, verts=40)]
    for o in p:
        o.scale = (1.0, 0.7, 1.0)
    piece("RugOval", p)
    p = [rbox("Rug", PURPLE, (0, 0, 0.01), (2.2, 1.5, 0.02), bevel=0.008, sub=0),
         rbox("Inner", CREAM, (0, 0, 0.016), (1.9, 1.2, 0.02), bevel=0.005, sub=0),
         rbox("Core", TEAL, (0, 0, 0.022), (1.4, 0.75, 0.02), rot=(0, 0, 3), bevel=0.005, sub=0)]
    piece("RugRect", p)

    # ---- fireplace: real open-fire anatomy (see CHIMNEY-RESEARCH.md) ----
    # Opening 0.9 wide x 0.75 high at the front (+Y), firebox 0.5 deep in buff firebrick with splayed
    # sides and a back that is vertical to 0.35 m then slopes forward to the throat. The throat (a
    # 0.9 x 0.2 slot at 0.95 m, 0.2 m above the opening) is open: the damper, smoke shelf and smoke
    # chamber above it are built by house.gd. Lintel and breast only at the front; projecting mantel.
    p = []
    FIREBRICK = mat("Firebrick", (0.5, 0.4, 0.3))
    FB_SOOT = mat("FireSoot", (0.13, 0.1, 0.09))
    for s in (-1, 1):
        p.append(wonk(rbox("Jamb%d" % s, BRICK, (s * 0.72, 0, 0.6), (0.55, 0.75, 1.2), bevel=0.04, sub=1), taper=-0.05))
    p.append(rbox("Lintel", BRICK, (0, 0.265, 0.85), (1.0, 0.22, 0.2), bevel=0.03, sub=1))
    p.append(rbox("Breast", BRICK, (0, 0.265, 1.08), (1.0, 0.22, 0.26), bevel=0.03, sub=1))
    # firebox: back (vertical lower, sloped upper), splayed sides, inner hearth
    p.append(rbox("FireBack", FB_SOOT, (0, -0.3, 0.175), (0.55, 0.1, 0.35), bevel=0.01, sub=0))
    p.append(rbox("FireBackSlope", FB_SOOT, (0, -0.2, 0.62), (0.62, 0.1, 0.62), rot=(-22, 0, 0), bevel=0.01, sub=0))
    for s in (-1, 1):
        p.append(rbox("FireSide%d" % s, FIREBRICK, (s * 0.41, 0.0, 0.47), (0.1, 0.56, 0.94), rot=(0, 0, -s * 19.3), bevel=0.01, sub=0))
    p.append(rbox("FireFloor", FIREBRICK, (0, 0.0, 0.01), (0.9, 0.5, 0.02), bevel=0.0, sub=0))
    for i in range(4):  # (keeps the shared random stream the same for the pieces after this one)
        rnd.uniform(-0.25, 0.25)
    p.append(rbox("Mantel", WOOD_D, (0, 0.42, 1.25), (2.2, 0.32, 0.1), rot=(0, 1.5, 0), bevel=0.03, sub=1))
    p.append(rbox("Hearth", STONE, (0, 0.55, 0.03), (2.1, 0.6, 0.06), bevel=0.02, sub=1))
    p.append(tube("Garland", GREEN, [(-1.05, 0.55, 1.25), (-0.5, 0.6, 1.12), (0, 0.62, 1.18), (0.5, 0.6, 1.12), (1.05, 0.55, 1.25)], 0.05))
    p.append(cyl("Clock", WOOD, (0.7, 0.33, 1.42), 0.12, 0.08, rot=(90, 0, 0)))
    p.append(cyl("ClockFace", WHITE, (0.7, 0.38, 1.42), 0.09, 0.02, rot=(90, 0, 0)))
    piece("Fireplace", p)

    # ---- artificial Christmas tree in a bucket, baubles, tinsel, fairy lights, star ----
    p = [cyl("Bucket", REDF, (0, 0, 0.17), 0.26, 0.34, r2=0.32, verts=20), cyl("Trunk", WOOD_D, (0, 0, 0.4), 0.05, 0.3)]
    tiers = [(0.5, 0.85, 0.65), (0.95, 0.68, 0.6), (1.35, 0.5, 0.55), (1.7, 0.32, 0.5)]
    for i, (z, r, h) in enumerate(tiers):
        c = cyl("Tier%d" % i, GREEN if i % 2 == 0 else GREEN_D, (rnd.uniform(-0.03, 0.03), rnd.uniform(-0.03, 0.03), z + h / 2), r, h, r2=0.04, verts=12, rot=(rnd.uniform(-4, 4), rnd.uniform(-4, 4), i * 15))
        p.append(wonk(c, bend=rnd.uniform(-8, 8)))
    for k in range(18):
        t = rnd.random()
        z = 0.6 + t * 1.45
        r = 0.82 * (1 - t) + 0.12
        a = rnd.uniform(0, math.tau)
        p.append(sphere("Bauble", BAUBLES[k % 4], (math.cos(a) * r, math.sin(a) * r, z), 0.055))
    pts = []
    for i in range(60):
        t = i / 59
        a = t * math.tau * 4.5
        r = 0.86 * (1 - t) + 0.14
        pts.append((math.cos(a) * r, math.sin(a) * r, 0.62 + t * 1.5))
    p.append(tube("Tinsel", GOLD, pts[::3], 0.018))
    for i, q in enumerate(pts[::2]):
        p.append(sphere("Light", BULBS[i % 5], (q[0] * 1.04, q[1] * 1.04, q[2] - 0.05), 0.028))
    star = mat("StarGlow", (1.0, 0.85, 0.3), emit=3.0)
    p.append(sphere("Star", star, (0, 0, 2.28), 0.11, scale=(1, 0.4, 1)))
    for k in range(5):
        a = math.radians(90 + k * 72)
        p.append(cyl("Ray", star, (math.cos(a) * 0.12, 0, 2.28 + math.sin(a) * 0.12), 0.05, 0.14, r2=0.0, verts=8, rot=(0, -math.degrees(a) + 90, 0)))
    piece("ChristmasTree", p)

    # ---- stocking (hangs from its origin, toe to +X) ----
    p = [tube("Leg", REDF, [(0, 0, -0.05), (0, 0, -0.3), (0.04, 0, -0.42), (0.16, 0, -0.45)], 0.075, taper_end=0.9),
         cyl("Cuff", WHITE, (0, 0, -0.05), 0.09, 0.1, verts=16, sub=1), cyl("Loop", GOLD, (0, 0, 0.02), 0.015, 0.06)]
    piece("Stocking", p)

    # ---- plants ----
    p = [cyl("Pot", POT, (0, 0, 0.2), 0.2, 0.4, r2=0.25, verts=16, bevel=0.02), cyl("Soil", WOOD_D, (0, 0, 0.39), 0.23, 0.02)]
    for k in range(9):
        a = k * math.tau / 9 + rnd.uniform(-0.2, 0.2)
        L = rnd.uniform(0.45, 0.8)
        tip = (math.cos(a) * L * 0.7, math.sin(a) * L * 0.7, 0.4 + L)
        p.append(tube("Stem", LEAF, [(0, 0, 0.4), (tip[0] * 0.4, tip[1] * 0.4, 0.4 + L * 0.7), tip], 0.012))
        p.append(sphere("Leaf", LEAF, tip, 0.13, scale=(1.0, 0.45, 0.12), rot=(rnd.uniform(-30, 30), 40, math.degrees(a))))
    piece("Plant", p)

    # ---- pictures (hang on a wall, face +Y) ----
    for n, (w, h, c) in {"PictureA": (0.7, 0.5, (0.95, 0.6, 0.25)), "PictureB": (0.45, 0.6, (0.3, 0.6, 0.85))}.items():
        q = [rbox("Frame", GOLD if n == "PictureA" else WOOD_D, (0, 0, 0), (w, 0.04, h), bevel=0.01, sub=0),
             rbox("Canvas", mat("Canvas" + n, c), (0, 0.022, 0), (w - 0.1, 0.01, h - 0.1), bevel=0.0, sub=0),
             sphere("Sun", mat("CanvasSun", (1, 0.9, 0.4)), (w * 0.2, 0.03, h * 0.18), 0.06, scale=(1, 0.2, 1)),
             rbox("Hill", mat("CanvasHill", (0.25, 0.55, 0.3)), (0, 0.03, -h * 0.25), (w - 0.12, 0.01, h * 0.25), rot=(0, 8, 0), bevel=0.0, sub=0)]
        piece(n, q)

    # ---- snacks: cookies + milk, and the Aussie beer + carrot for the reindeer ----
    p = [cyl("Plate", WHITE, (0, 0, 0.01), 0.14, 0.02, verts=24, bevel=0.005)]
    for k in range(4):
        p.append(cyl("Cookie", WOOD_L, (rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05), 0.03 + k * 0.016), 0.055, 0.014, verts=14, rot=(rnd.uniform(-6, 6), 0, 0)))
    p.append(cyl("Glass", mat("Milk", (0.98, 0.98, 1.0)), (0.2, 0.0, 0.08), 0.04, 0.16, r2=0.045, verts=16))
    p.append(rbox("Note", CREAM, (-0.08, 0.16, 0.005), (0.12, 0.08, 0.004), rot=(0, 0, 12), bevel=0.0, sub=0))
    piece("CookiesMilk", p)
    BEER = mat("BeerBrown", (0.45, 0.22, 0.06))
    p = [cyl("Bottle", BEER, (0, 0, 0.09), 0.04, 0.18, verts=16, sub=1),
         cyl("Neck", BEER, (0, 0, 0.22), 0.016, 0.08, r2=0.014, verts=12),
         cyl("Label", GOLD, (0, 0, 0.09), 0.042, 0.07, verts=16),
         cyl("Carrot", mat("Carrot", (1.0, 0.5, 0.08)), (0.13, 0.0, 0.025), 0.03, 0.2, r2=0.004, verts=12, rot=(0, 90, 15)),
         tube("Tops", LEAF, [(0.02, 0, 0.03), (-0.04, 0.02, 0.06), (-0.07, 0.0, 0.08)], 0.01)]
    piece("BeerCarrot", p)

    # ---- cooling: pedestal fan + split-system air con ----
    p = [cyl("Base", WHITE, (0, 0, 0.03), 0.2, 0.06, verts=20, bevel=0.01), cyl("Pole", WHITE, (0, 0, 0.5), 0.025, 0.9),
         sphere("Motor", WHITE, (0, -0.06, 1.0), 0.08, scale=(1, 1.3, 1)),
         torus("Cage", METAL, (0, 0.06, 1.0), 0.24, 0.01, rot=(90, 0, 0)),
         torus("Cage2", METAL, (0, 0.1, 1.0), 0.16, 0.008, rot=(90, 0, 0))]
    FANB = mat("FanBlue", (0.5, 0.75, 0.95))
    for k in range(3):
        a = k * 120
        p.append(sphere("Blade%d" % k, FANB, (math.cos(math.radians(a)) * 0.12, 0.05, 1.0 + math.sin(math.radians(a)) * 0.12), 0.11, scale=(1, 0.08, 0.45), rot=(0, -a, 0)))
    piece("Fan", p)
    p = [wonk(rbox("Body", WHITE, (0, 0, 0), (0.95, 0.25, 0.3), bevel=0.08, sub=2), bend=3, axis="X"),
         rbox("Vent", METAL, (0, 0.11, -0.1), (0.8, 0.04, 0.05), bevel=0.01, sub=0),
         sphere("Led", mat("AcGlow", (0.3, 1.0, 0.5), emit=3.0), (0.38, 0.13, 0.05), 0.012)]
    piece("AirCon", p)

    # ---- presents (stack under the tree) ----
    for n, (s, c, r) in {"PresentA": ((0.32, 0.32, 0.26), REDF, GOLD), "PresentB": ((0.45, 0.3, 0.2), BLUE, WHITE), "PresentC": ((0.22, 0.22, 0.34), LEAF, REDF)}.items():
        q = [rbox("Box", c, (0, 0, s[2] / 2), s, bevel=0.015, sub=1),
             rbox("RibbonX", r, (0, 0, s[2] / 2), (s[0] + 0.01, 0.05, s[2] + 0.01), bevel=0.003, sub=0),
             rbox("RibbonY", r, (0, 0, s[2] / 2), (0.05, s[1] + 0.01, s[2] + 0.01), bevel=0.003, sub=0),
             torus("Bow", r, (0, 0, s[2] + 0.03), 0.04, 0.015, rot=(90, 0, 30))]
        piece(n, q)

    # ---- interior door (hinge at x = 0; slab extends +X) ----
    p = [rbox("Slab", WOOD_L, (0.45, 0, 1.0), (0.9, 0.05, 2.0), bevel=0.02, sub=1),
         rbox("PanelT", WOOD, (0.45, 0.03, 1.45), (0.62, 0.02, 0.6), bevel=0.01, sub=0),
         rbox("PanelB", WOOD, (0.45, 0.03, 0.55), (0.62, 0.02, 0.7), bevel=0.01, sub=0),
         sphere("Knob", GOLD, (0.8, 0.06, 1.0), 0.035)]
    piece("InteriorDoor", p)

    # ---- under-bed clutter (no collision; purely for fun) ----
    p = [rbox("Box", mat("ShoeboxOrange", (0.95, 0.5, 0.15)), (0, 0, 0.06), (0.34, 0.2, 0.12), bevel=0.01, sub=0),
         rbox("Lid", mat("ShoeboxLid", (0.98, 0.62, 0.25)), (0.02, 0.0, 0.125), (0.36, 0.22, 0.025), rot=(0, 0, 6), bevel=0.008, sub=0),
         rbox("Logo", WHITE, (0.02, 0.112, 0.07), (0.12, 0.004, 0.04), bevel=0.0, sub=0)]
    piece("Shoebox", p)
    SOCK = mat("SockStripe", (0.9, 0.2, 0.25))
    p = [tube("Sock", SOCK, [(-0.12, 0, 0.02), (0.04, 0.01, 0.02), (0.1, 0.05, 0.02), (0.11, 0.1, 0.02)], 0.03, taper_end=0.85)]
    for k in range(3):
        p.append(torus("Stripe%d" % k, WHITE, (-0.08 + k * 0.06, 0.0, 0.02), 0.031, 0.006, rot=(0, 90, 0)))
    piece("LostSock", p)
    p = [rbox("Car", BLUE, (0, 0, 0.045), (0.16, 0.08, 0.05), bevel=0.012, sub=1),
         rbox("Cab", WHITE, (-0.01, 0, 0.08), (0.08, 0.07, 0.035), bevel=0.01, sub=1)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(cyl("Wheel", BLACK, (sx * 0.05, sy * 0.042, 0.02), 0.02, 0.015, rot=(90, 0, 0), verts=12))
    p.append(sphere("Ball", REDF, (0.22, 0.08, 0.05), 0.05))
    piece("ToyCar", p)

    # Nightlight (plugs into a wall, glows): a little moon
    p = [rbox("Plug", WHITE, (0, 0, 0), (0.08, 0.04, 0.1), bevel=0.01, sub=0),
         sphere("Moon", mat("NightlightGlow", (0.6, 0.85, 1.0), emit=3.0), (0, 0.04, 0.02), 0.05, scale=(1, 0.5, 1))]
    piece("Nightlight", p)

    export(furn, "furniture.glb")
    return furn


def build_elf():
    """Modelled at ~0.6 m and scaled in Godot to the shared standing height (scripts/elf_size.gd,
    0.22 m: ankle-to-shin on an adult). Skinny, mischievous stealth elf after
    art/reference/elf_stealth_reference.png: big pointy ears, pointy nose, dark green/black tactical
    gear, floppy dark-green hat with a red-orange pom-pom, glowing green night-vision goggles
    (material "GoggleGlow"), curly shoes and a candy cane. Pivots for procedural animation:
    Elf > Hips > (Head, ArmL, ArmR), Elf > LegL / LegR.  Faces +Y (Godot -Z)."""
    elf = collection("Elf")
    SKIN = mat("ElfSkin", (0.95, 0.72, 0.58))
    SUIT = mat("ElfSuit", (0.1, 0.2, 0.12))
    SUIT_D = mat("ElfSuitDark", (0.05, 0.08, 0.06))
    HAT = mat("ElfHat", (0.09, 0.3, 0.14))
    POM = mat("ElfPom", (0.95, 0.16, 0.1))
    STRAP = mat("ElfStrap", (0.04, 0.04, 0.05))
    GOG = mat("GoggleGlow", (0.35, 1.0, 0.25), emit=6.0)
    BUCKLE = mat("ElfBuckle", (0.85, 0.7, 0.25))
    CANE_R = mat("CaneRed", (0.95, 0.1, 0.1))
    CANE_W = mat("CaneWhite", (0.98, 0.96, 0.94))

    hip_z = 0.17
    torso = meta("ElfTorso", SUIT, [("e", (0, 0, 0.26), (0.07, 0.055, 0.1)), ("e", (0, 0.0, 0.18), (0.065, 0.052, 0.05))], res=0.008)
    vest = rbox("ElfVest", SUIT_D, (0, 0.03, 0.27), (0.11, 0.05, 0.12), bevel=0.02, sub=1)
    belt = torus("ElfBelt", STRAP, (0, 0, 0.19), 0.066, 0.013, scale=(1, 0.85, 1))
    buckle = rbox("ElfBeltBuckle", BUCKLE, (0, 0.058, 0.19), (0.035, 0.012, 0.028), bevel=0.004, sub=0)
    pouch = rbox("ElfPouch", SUIT_D, (0.06, 0.04, 0.17), (0.04, 0.035, 0.045), bevel=0.01, sub=1)
    head_z = 0.39
    head = meta("ElfHead", SKIN, [("e", (0, 0, head_z), (0.075, 0.07, 0.08)), ("e", (0, 0.02, head_z - 0.04), (0.055, 0.055, 0.045))], res=0.006)
    nose = cyl("ElfNose", SKIN, (0, 0.11, head_z - 0.03), 0.018, 0.1, r2=0.003, verts=12, rot=(-76, 0, 0), sub=1)
    ears = []
    for s in (-1, 1):
        # ears come out from under the hat brim, swept up and back
        e = cyl("ElfEar%d" % s, SKIN, (s * 0.125, -0.015, head_z + 0.012), 0.032, 0.18, r2=0.002, verts=12, rot=(-12, s * 56, 0), sub=1)
        e.scale = (1, 0.4, 1)
        ears.append(e)
    grin = torus("ElfGrin", mat("ElfMouth", (0.45, 0.12, 0.12)), (0, 0.062, head_z - 0.062), 0.02, 0.005, rot=(90, 0, 0), scale=(1.4, 1, 0.5))
    # night-vision goggles on a strap round the head at eye level, clear below the hat brim
    gz = head_z + 0.008
    strap = torus("GoggleStrap", STRAP, (0, 0, gz), 0.077, 0.01, scale=(1, 0.95, 1))
    goggles = []
    for s in (-1, 1):
        goggles.append(cyl("GoggleBarrel%d" % s, STRAP, (s * 0.032, 0.07, gz), 0.024, 0.04, rot=(90, 0, 0)))
        goggles.append(cyl("GoggleLens%d" % s, GOG, (s * 0.032, 0.091, gz), 0.019, 0.006, rot=(90, 0, 0)))
    # floppy pointed hat sitting ON the head: a brim band round the crown (above the goggles and
    # ears), a soft cone that flops back, a red pom-pom on the tip. Pivots: Hat (on the brim) >
    # HatCone (back of the cone's base: elf.gd squashes and folds the cone under low furniture
    # without moving the brim, so it never sinks into the head).
    hb = head_z + 0.064
    brim = torus("ElfHatBrim", HAT, (0, 0, hb), 0.062, 0.014)
    hat_pts = [(0, 0.0, hb + 0.004), (0, -0.006, hb + 0.075), (0, -0.035, hb + 0.13), (0, -0.08, hb + 0.155), (0, -0.115, hb + 0.13)]
    hat = tube("ElfHatCone", HAT, hat_pts, 0.072, radii=[1.0, 0.82, 0.52, 0.28, 0.14])
    pom = sphere("ElfPomPom", POM, (0, -0.122, hb + 0.115), 0.024)
    cone_pv = pivot_group("HatCone", (0, -0.06, hb + 0.004), [hat, pom])
    hat_pv = pivot_group("Hat", (0, 0, hb), [brim, cone_pv])
    head_pv = pivot_group("Head", (0, 0, head_z - 0.06), [head, nose, *ears, grin, strap, *goggles, hat_pv])
    arm_pvs = []
    for s, nm in ((1, "ArmR"), (-1, "ArmL")):
        sh = (s * 0.075, 0, 0.32)
        hand = (s * 0.12, 0.05, 0.2)
        parts = [tube("ElfArm%s" % nm, SUIT, [sh, (s * 0.11, 0.02, 0.26), hand], 0.017), sphere("ElfHand%s" % nm, SUIT_D, hand, 0.024)]
        if s == 1:
            pts = [(hand[0], hand[1] + 0.01, hand[2] - 0.08), (hand[0], hand[1] + 0.01, hand[2] + 0.09),
                   (hand[0], hand[1] + 0.04, hand[2] + 0.12), (hand[0], hand[1] + 0.07, hand[2] + 0.09)]
            parts.append(tube("CandyCane", CANE_W, pts, 0.008))
            for k in range(5):
                parts.append(torus("CaneStripe%d" % k, CANE_R, (hand[0], hand[1] + 0.01, hand[2] - 0.06 + k * 0.034), 0.009, 0.0035, rot=(15, 0, 0)))
        arm_pvs.append(pivot_group(nm, sh, parts))
    hips = pivot_group("Hips", (0, 0, hip_z), [torso, vest, belt, buckle, pouch, head_pv, *arm_pvs])
    legs = []
    for s, nm in ((1, "LegR"), (-1, "LegL")):
        top = (s * 0.035, 0, hip_z)
        leg = tube("ElfLeg%s" % nm, SUIT_D, [top, (s * 0.04, 0.005, 0.1), (s * 0.04, 0.0, 0.03)], 0.019)
        shoe = tube("ElfShoe%s" % nm, SUIT_D, [(s * 0.04, -0.02, 0.02), (s * 0.04, 0.03, 0.018), (s * 0.04, 0.07, 0.03), (s * 0.04, 0.075, 0.06)], 0.022, taper_end=0.2)
        legs.append(pivot_group(nm, top, [leg, shoe]))
    pivot_group("Elf", (0, 0, 0), [hips, *legs])
    export(elf, "elf.glb")
    return elf


if ONLY:
    if "interiors" in ONLY:
        build_interiors()
    if "elf" in ONLY:
        build_elf()
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        scn = bpy.context.scene
        scn.render.engine = "CYCLES"
        scn.cycles.samples = 16
        scn.cycles.device = "CPU"
        scn.render.resolution_x = 1400
        scn.render.resolution_y = 700
        world = bpy.data.worlds.new("w")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.27, 0.4, 1)
        scn.world = world
        collection("Preview")
        sun = bpy.data.lights.new("sun", "SUN")
        sun.energy = 3.5
        so = link(bpy.data.objects.new("sun", sun))
        so.rotation_euler = (math.radians(50), 0, math.radians(30))
        cam = bpy.data.cameras.new("cam")
        co = link(bpy.data.objects.new("cam", cam))
        scn.camera = co
        if "interiors" in ONLY:
            tops = [o for o in bpy.data.collections["Furniture"].objects if o.parent is None]
            n = (len(tops) + 1) // 2
            for half, sel in enumerate((tops[:n], tops[n:])):
                for o in tops:
                    hide = o not in sel
                    for c in o.children_recursive:
                        c.hide_render = hide
                xs = 0.0
                for o in sel:
                    o.location = (xs, 0, 0)
                    xs += 2.4
                mid = (xs - 2.4) / 2
                co.location = (mid, -mid * 1.1 - 4, mid * 0.5 + 2.5)
                d = Vector((mid, 0, 0.7)) - Vector(co.location)
                co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
                cam.lens = 30
                scn.render.filepath = os.path.join(PREVIEW, "furniture_%d.png" % half)
                bpy.ops.render.render(write_still=True)
            for o in tops:
                for c in o.children_recursive:
                    c.hide_render = True
        if "elf" in ONLY:
            cam.lens = 50
            for nm, pos in {"elf_front": (0.55, 1.4, 0.55), "elf_side": (1.5, 0.3, 0.4)}.items():
                co.location = pos
                d = Vector((0, 0, 0.3)) - Vector(pos)
                co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
                scn.render.filepath = os.path.join(PREVIEW, nm + ".png")
                bpy.ops.render.render(write_still=True)
    sys.exit(0)


# =================================================================================================
# SLEIGH
# =================================================================================================
RED = mat("SleighRed", (0.86, 0.07, 0.06))
DARK_RED = mat("SleighDarkRed", (0.5, 0.04, 0.05))
GOLD = mat("Gold", (1.0, 0.72, 0.14))
VELVET = mat("Velvet", (0.52, 0.22, 0.7))
GLOW = mat("GlowLantern", (1.0, 0.8, 0.35), emit=4.0)
SACK = mat("Sack", (0.62, 0.4, 0.2))
ROPE = mat("Rope", (0.95, 0.82, 0.45))
GIFT_G = mat("GiftGreen", (0.1, 0.6, 0.3))
GIFT_B = mat("GiftBlue", (0.15, 0.45, 0.95))
RIBBON = mat("Ribbon", (1.0, 0.85, 0.2))
RIBBON_R = mat("RibbonRed", (0.95, 0.1, 0.12))

sleigh = collection("Sleigh")
panel_pts = [(-1.5, -0.32), (0.8, -0.32), (1.2, -0.18), (1.42, 0.12), (1.44, 0.5), (1.28, 0.76),
             (1.02, 0.8), (0.84, 0.62), (0.6, 0.36), (0.0, 0.28), (-0.45, 0.33), (-0.72, 0.5),
             (-1.02, 0.56), (-1.3, 0.76), (-1.46, 1.02), (-1.64, 1.04), (-1.68, 0.6), (-1.62, 0.0)]
for sx in (-1, 1):
    side_slab("SidePanel%s" % ("L" if sx < 0 else "R"), RED, panel_pts, sx * 0.69, 0.06, 0.035)
    # Gold trim along the top edge and two big scrolls on the outside of each panel.
    top = [(1.28, 0.76), (1.02, 0.8), (0.84, 0.62), (0.6, 0.36), (0.0, 0.28), (-0.45, 0.33),
           (-0.72, 0.5), (-1.02, 0.56), (-1.3, 0.76), (-1.46, 1.02)]
    tube("TrimTop", GOLD, [(sx * 0.73, y, z + 0.01) for y, z in top], 0.035)
    tube("ScrollFront", GOLD, spiral(1.12, 0.42, sx * 0.79, 0.27, 0.05, 1.6, 100, direction=-1), 0.032)
    tube("ScrollBack", GOLD, spiral(-1.42, 0.62, sx * 0.79, 0.24, 0.05, 1.5, 80, direction=1), 0.03)
    tube("TrimBottom", GOLD, [(sx * 0.77, y, -0.28) for y in (-1.55, -0.8, 0.0, 0.8, 1.15)], 0.03)

# Solid curved nose between the panels, rear wall, floor, seat and seat back.
side_slab("Nose", RED, [(0.7, -0.32), (1.18, -0.2), (1.37, 0.1), (1.38, 0.5), (1.22, 0.72),
                        (1.0, 0.74), (0.86, 0.6), (0.95, 0.38), (0.98, 0.0), (0.8, -0.16)], 0.0, 0.64, 0.03)
side_slab("BackWall", RED, [(-1.42, -0.32), (-1.28, -0.32), (-1.28, 0.62), (-1.4, 0.92), (-1.58, 0.92),
                            (-1.6, 0.4), (-1.58, -0.2)], 0.0, 0.64, 0.03)
rbox("Floor", DARK_RED, (0, -0.3, -0.24), (1.3, 2.4, 0.16), bevel=0.04, sub=1)
rbox("SeatCushion", VELVET, (0, -0.02, -0.03), (1.24, 0.62, 0.28), bevel=0.08, sub=2)
side_slab("SeatBack", RED, [(-0.36, -0.15), (-0.32, 0.55), (-0.4, 0.88), (-0.56, 0.96), (-0.6, 0.6),
                            (-0.52, -0.15)], 0.0, 0.64, 0.03)
rbox("SeatBackCushion", VELVET, (0, -0.31, 0.38), (1.16, 0.14, 0.62), rot=(-8, 0, 0), bevel=0.06, sub=2)
tube("SeatBackTrim", GOLD, [(-0.66, -0.55, 0.97), (-0.3, -0.5, 1.0), (0.3, -0.5, 1.0), (0.66, -0.55, 0.97)], 0.04)

# Runners: one continuous gold tube per side with a big front curl and a little rear flick.
runner = [(-1.78, -0.4), (-1.6, -0.57), (-1.2, -0.6), (0.0, -0.6), (1.1, -0.6), (1.55, -0.52), (1.82, -0.25),
          (1.82, 0.1), (1.62, 0.28), (1.42, 0.18), (1.42, -0.02), (1.58, -0.04)]
for sx in (-1, 1):
    x = sx * 0.7
    tube("Runner", GOLD, [(x, y, z) for y, z in runner], 0.06)
    for y in (-1.15, -0.2, 0.75):
        tube("Strut", GOLD, [(x, y - 0.06, -0.6), (x, y + 0.02, -0.48), (x * 0.98, y - 0.02, -0.38), (x * 0.96, y + 0.04, -0.28)], 0.035)
    tube("CurlBrace", GOLD, [(x, 1.42, -0.02), (x, 1.36, 0.02), (x * 0.97, 1.3, 0.05)], 0.03)
    # Lantern on a gold post at the front corners
    lp = tube("LanternPost", GOLD, [(sx * 0.6, 1.12, 0.74), (sx * 0.62, 1.16, 0.92), (sx * 0.62, 1.18, 1.02)], 0.025)
    lb = sphere("Lantern", GLOW, (sx * 0.62, 1.18, 1.1), 0.09, (1, 1, 1.15))
    lc = sphere("LanternCap", GOLD, (sx * 0.62, 1.18, 1.21), 0.06, (1, 1, 0.6))
    pivot_group("Lantern%s" % ("L" if sx < 0 else "R"), (sx * 0.6, 1.12, 0.74), [lp, lb, lc])

# Overstuffed toy sack in the rear compartment, plus presents.
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=(0.18, -1.02, 0.42), segments=32, ring_count=16)
s = bpy.context.active_object
s.name = "SackBody"
move_to_cur(s)
for v in s.data.vertices:
    p = v.co
    lump = 1.0 + 0.07 * math.sin(p.x * 13) * math.sin(p.y * 11 + 1.3) * math.cos(p.z * 9)
    p.x *= 0.9 * lump
    p.y *= 0.95 * lump
    p.z *= 1.15 if p.z < 0 else 1.05 * lump
    if p.z > 0.3:  # gather towards the neck
        k = (p.z - 0.3) / 0.25
        p.x *= 1 - 0.55 * k
        p.y *= 1 - 0.55 * k
s.rotation_euler = (math.radians(-8), math.radians(10), 0)
set_mat(s, SACK)
smooth(s, 1)
tie = torus("SackTie", ROPE, (0.23, -1.06, 0.98), 0.12, 0.04, rot=(-8, 10, 0))
bpy.ops.mesh.primitive_cone_add(radius1=0.06, radius2=0.2, depth=0.2, location=(0.24, -1.07, 1.1), vertices=24)
f = bpy.context.active_object
f.name = "SackTuft"
move_to_cur(f)
set_mat(f, SACK)
smooth(f, 2)
rbox("GiftA", GIFT_G, (0.02, -1.28, 0.0), (0.36, 0.3, 0.32), rot=(0, 0, 18), bevel=0.04, sub=1)
rbox("GiftARibbon1", RIBBON, (0.02, -1.28, 0.0), (0.38, 0.07, 0.34), rot=(0, 0, 18), bevel=0.02, sub=1)
rbox("GiftARibbon2", RIBBON, (0.02, -1.28, 0.0), (0.07, 0.32, 0.34), rot=(0, 0, 18), bevel=0.02, sub=1)
sphere("GiftABow", RIBBON, (0.02, -1.28, 0.2), 0.07, (1.4, 0.8, 0.7))
gb = rbox("GiftB", GIFT_B, (-0.05, -0.86, 1.0), (0.26, 0.26, 0.26), rot=(14, 8, -25), bevel=0.035, sub=1)
gbr = rbox("GiftBRibbon", RIBBON_R, (-0.05, -0.86, 1.0), (0.28, 0.06, 0.28), rot=(14, 8, -25), bevel=0.02, sub=1)

pivot_group("Sack", (0.18, -1.02, -0.12), [s, tie, f, gb, gbr])

# =================================================================================================
# SANTA (seated, in sleigh space)
# =================================================================================================
SUIT = mat("SantaSuit", (0.9, 0.08, 0.07))
FUR = mat("SantaFur", (0.98, 0.97, 0.94))
SKIN = mat("SantaSkin", (1.0, 0.78, 0.64))
CHEEK = mat("SantaCheek", (1.0, 0.45, 0.45))
NOSE = mat("SantaNose", (1.0, 0.55, 0.5))
BLACK = mat("Black", (0.06, 0.05, 0.06))
MITT = mat("SantaMitten", (0.12, 0.42, 0.2))
BUCKLE = GOLD
REIN = mat("Rein", (0.35, 0.18, 0.08))

santa = collection("Santa")
meta("SantaBody", SUIT, [
    ("e", (0, 0.04, 0.42), (0.44, 0.42, 0.42)),            # big round belly
    ("e", (0, -0.06, 0.8), (0.38, 0.3, 0.3)),              # chest/shoulders
    ("c", (-0.19, 0.0, 0.18), (-0.21, 0.5, 0.17), 0.16),   # thighs (sitting)
    ("c", (0.19, 0.0, 0.18), (0.21, 0.5, 0.17), 0.16),
    ("c", (-0.21, 0.52, 0.15), (-0.22, 0.6, -0.08), 0.12), # shins
    ("c", (0.21, 0.52, 0.15), (0.22, 0.6, -0.08), 0.12),
    ("c", (-0.36, -0.05, 0.9), (-0.5, 0.2, 0.66), 0.12),   # upper arms
    ("c", (0.36, -0.05, 0.9), (0.5, 0.2, 0.66), 0.12),
    ("c", (-0.5, 0.2, 0.66), (-0.34, 0.52, 0.7), 0.11),    # forearms reaching for the reins
    ("c", (0.5, 0.2, 0.66), (0.34, 0.52, 0.7), 0.11),
])
meta("SantaBoots", BLACK, [
    ("e", (-0.22, 0.68, -0.1), (0.13, 0.2, 0.1)),
    ("e", (0.22, 0.68, -0.1), (0.13, 0.2, 0.1)),
])
meta("SantaMitts", MITT, [
    ("e", (-0.32, 0.6, 0.72), (0.12, 0.13, 0.12)), ("e", (-0.24, 0.62, 0.77), (0.05, 0.05, 0.07)),
    ("e", (0.32, 0.6, 0.72), (0.12, 0.13, 0.12)), ("e", (0.24, 0.62, 0.77), (0.05, 0.05, 0.07)),
])
# Fur trims: coat hem, front placket, cuffs, boot tops
meta("SantaTrim", FUR, [
    ("e", (0, 0.43, 0.42), (0.1, 0.06, 0.38)),
    ("e", (0, 0.32, 0.78), (0.09, 0.05, 0.16)),
    ("c", (-0.42, 0.42, 0.68), (-0.4, 0.48, 0.71), 0.12),
    ("c", (0.42, 0.42, 0.68), (0.4, 0.48, 0.71), 0.12),
    ("c", (-0.22, 0.6, 0.05), (-0.22, 0.62, 0.0), 0.13),
    ("c", (0.22, 0.6, 0.05), (0.22, 0.62, 0.0), 0.13),
])
torus("SantaHem", FUR, (0, 0.04, 0.12), 0.4, 0.07, scale=(1.05, 1.0, 0.9))
torus("SantaBelt", BLACK, (0, 0.04, 0.42), 0.42, 0.06, scale=(1.04, 1.0, 0.8))
rbox("SantaBuckle", BUCKLE, (0, 0.47, 0.42), (0.2, 0.06, 0.15), bevel=0.02, sub=1)
rbox("SantaBuckleHole", BLACK, (0, 0.5, 0.42), (0.1, 0.03, 0.07), bevel=0.01, sub=1)
# Head and face
sphere("SantaHead", SKIN, (0, 0.0, 1.2), 0.27, (1.0, 0.95, 1.0))
sphere("SantaNose", NOSE, (0, 0.27, 1.17), 0.075, (1.0, 0.9, 0.85))
for sx in (-1, 1):
    sphere("SantaCheek", CHEEK, (sx * 0.14, 0.2, 1.13), 0.075, (1.0, 0.6, 0.8))
    sphere("SantaEyeWhite", FUR, (sx * 0.1, 0.222, 1.27), 0.068, (1.0, 0.6, 1.1))
    sphere("SantaPupil", BLACK, (sx * 0.1, 0.262, 1.265), 0.04, (1.0, 0.6, 1.0))
    sphere("SantaGlint", FUR, (sx * 0.088, 0.283, 1.282), 0.013)
    sphere("SantaBrow", FUR, (sx * 0.11, 0.215, 1.345), 0.065, (1.2, 0.5, 0.45), rot=(0, sx * -12, 0))
meta("SantaBeard", FUR, [
    ("e", (0, 0.13, 1.0), (0.26, 0.16, 0.22)),
    ("e", (-0.17, 0.08, 1.1), (0.12, 0.12, 0.16)),
    ("e", (0.17, 0.08, 1.1), (0.12, 0.12, 0.16)),
    ("e", (0, 0.17, 0.84), (0.13, 0.09, 0.12)),
    ("e", (-0.24, -0.02, 1.2), (0.06, 0.1, 0.12)),
    ("e", (0.24, -0.02, 1.2), (0.06, 0.1, 0.12)),
])
meta("SantaMoustache", FUR, [
    ("e", (-0.08, 0.27, 1.1), (0.1, 0.05, 0.045), (0, -15, 0)),
    ("e", (0.08, 0.27, 1.1), (0.1, 0.05, 0.045), (0, 15, 0)),
])
# Floppy hat: bent cone + fur band + pom-pom
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=28, radius1=0.29, radius2=0.012, depth=0.62)
for v in bm.verts:
    t = (v.co.z + 0.31) / 0.62
    v.co.z = 0.31 * 0 + t * 0.5 - 0.12 * t ** 3
    v.co.y -= 0.42 * t ** 2
    v.co.x += 0.06 * t ** 2
me = bpy.data.meshes.new("SantaHat")
bm.to_mesh(me)
bm.free()
hat = link(bpy.data.objects.new("SantaHat", me))
hat.location = (0, -0.03, 1.42)
set_mat(hat, SUIT)
smooth(hat, 2)
torus("SantaHatBand", FUR, (0, -0.03, 1.43), 0.26, 0.07, rot=(-8, 0, 0))
sphere("SantaPompom", FUR, (0.06, -0.45, 1.81), 0.1)
# Reins from the mitts to the front of the sleigh (the game continues them to the reindeer)
for sx in (-1, 1):
    tube("Rein", REIN, [(sx * 0.3, 0.64, 0.72), (sx * 0.3, 0.95, 0.66), (sx * 0.34, 1.2, 0.72), (sx * 0.35, 1.3, 0.76)], 0.018)

# =================================================================================================
# REINDEER (origin at body centre; legs are separate objects pivoting at the hip for the gallop)
# =================================================================================================
DFUR = mat("DeerFur", (0.62, 0.36, 0.17))
DLIGHT = mat("DeerLight", (0.96, 0.84, 0.66))
HOOF = mat("DeerHoof", (0.16, 0.1, 0.08))
ANTLER = mat("Antler", (0.96, 0.87, 0.62))
EYE = mat("DeerEyeWhite", (0.98, 0.98, 0.97))
PUPIL = mat("DeerPupil", (0.05, 0.04, 0.05))
DNOSE = mat("Nose", (0.1, 0.07, 0.07))
COLLAR = mat("Collar", (0.85, 0.08, 0.08))
BELL = mat("Bell", (1.0, 0.75, 0.15))

deer = collection("Reindeer")
meta("DeerBody", DFUR, [
    ("e", (0, -0.02, 0.0), (0.27, 0.52, 0.3)),             # barrel body
    ("e", (0, 0.3, 0.06), (0.25, 0.25, 0.3)),             # chest
    ("e", (0, -0.36, 0.04), (0.25, 0.22, 0.27)),          # rump
    ("c", (0, 0.3, 0.12), (0, 0.4, 0.28), 0.14),          # neck root (the Head pivot sits inside it)
])
meta("DeerLightPatches", DLIGHT, [
    ("e", (0, 0.4, 0.0), (0.16, 0.14, 0.2)),              # chest bib
    ("e", (0, -0.03, -0.18), (0.18, 0.4, 0.1)),           # belly
])
# Head rig: Head (pivot at the neck root) > neck+head, muzzle, eyes, nose, antlers, EarL/EarR pivots.
head_parts = [meta("HeadMesh", DFUR, [
    ("c", (0, 0.34, 0.18), (0, 0.55, 0.52), 0.13),        # neck
    ("e", (0, 0.66, 0.62), (0.19, 0.24, 0.19)),           # head
])]
head_parts.append(meta("Muzzle", DLIGHT, [("e", (0, 0.86, 0.56), (0.13, 0.14, 0.11))]))
for sx in (-1, 1):
    head_parts.append(sphere("DeerEye", EYE, (sx * 0.1, 0.8, 0.69), 0.065, (0.8, 0.7, 1.0)))
    head_parts.append(sphere("DeerPupil", PUPIL, (sx * 0.1, 0.845, 0.695), 0.038, (0.8, 0.6, 1.0)))
    head_parts.append(sphere("DeerGlint", EYE, (sx * 0.09, 0.865, 0.71), 0.011))
    # Branching antlers (main beam + three tines)
    head_parts.append(tube("Antler", ANTLER, [(sx * 0.07, 0.62, 0.76), (sx * 0.17, 0.57, 0.95), (sx * 0.3, 0.47, 1.1), (sx * 0.38, 0.5, 1.3)], 0.034, taper_end=0.6))
    head_parts.append(tube("Tine", ANTLER, [(sx * 0.17, 0.57, 0.95), (sx * 0.2, 0.66, 1.05), (sx * 0.2, 0.76, 1.12)], 0.026, taper_end=0.6))
    head_parts.append(tube("Tine", ANTLER, [(sx * 0.29, 0.48, 1.09), (sx * 0.32, 0.58, 1.2), (sx * 0.31, 0.66, 1.3)], 0.024, taper_end=0.6))
    head_parts.append(tube("Tine", ANTLER, [(sx * 0.35, 0.48, 1.22), (sx * 0.45, 0.43, 1.3), (sx * 0.52, 0.42, 1.38)], 0.022, taper_end=0.6))
    ear = meta("EarMesh%s" % ("L" if sx < 0 else "R"), DFUR,
               [("e", (sx * 0.15, 0.6, 0.78), (0.11, 0.04, 0.06), (0, sx * 35, sx * 20))])
    head_parts.append(pivot_group("Ear%s" % ("L" if sx < 0 else "R"), (sx * 0.09, 0.6, 0.74), [ear]))
head_parts.append(sphere("DeerNose", DNOSE, (0, 0.98, 0.58), 0.07, (1.1, 0.9, 0.9)))
pivot_group("Head", (0, 0.34, 0.2), head_parts)
tail = meta("TailMesh", DLIGHT, [("e", (0, -0.58, 0.18), (0.07, 0.08, 0.1), (25, 0, 0))])
pivot_group("Tail", (0, -0.5, 0.12), [tail])
torus("Collar", COLLAR, (0, 0.42, 0.24), 0.17, 0.045, rot=(55, 0, 0), scale=(1.0, 1.0, 1.0))
sphere("CollarBell", BELL, (0, 0.53, 0.1), 0.055)
torus("Harness", COLLAR, (0, 0.04, 0.0), 0.3, 0.04, rot=(90, 0, 0), scale=(1.02, 1.0, 1.08))
sphere("HarnessBell", BELL, (0, 0.06, 0.33), 0.045)
for sx in (-1, 1):
    sphere("HarnessBellSide", BELL, (sx * 0.29, 0.06, 0.1), 0.04)

for name, (x, y, front) in {"LegFL": (-0.14, 0.3, True), "LegFR": (0.14, 0.3, True),
                            "LegBL": (-0.14, -0.34, False), "LegBR": (0.14, -0.34, False)}.items():
    hip = Vector((x, y, -0.08))
    thigh_r = 0.1 if front else 0.13
    leg = meta(name, DFUR, [
        ("c", (x, y, -0.02), (x, y + (0.0 if front else -0.03), -0.36), thigh_r),
        ("c", (x, y + (0.0 if front else -0.03), -0.36), (x, y, -0.6), 0.055),
    ])
    hoof = meta(name + "Hoof", HOOF, [("e", (x, y + 0.01, -0.64), (0.065, 0.075, 0.05))])
    # Pivot the leg at the hip so Godot can swing it.
    for o in (leg, hoof):
        o.data.transform(Matrix.Translation(-hip))
        o.location = hip
    hoof.parent = leg
    hoof.location = (0, 0, 0)

# Join all non-leg deer parts into a single body mesh per material is not needed; keep objects.

export(sleigh, "sleigh.glb")
export(santa, "santa.glb")
export(deer, "reindeer.glb")
build_interiors()
build_elf()

# ---- optional preview render (Cycles, CPU) ---------------------------------------------------
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 24
    scn.cycles.device = "CPU"
    scn.render.resolution_x = 900
    scn.render.resolution_y = 700
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.2, 0.35, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scn.world = world
    preview = collection("Preview")
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.0
    so = link(bpy.data.objects.new("sun", sun))
    so.rotation_euler = (math.radians(50), 0, math.radians(30))
    # Place a reindeer pair in front of the sleigh for the preview.
    deer_objs = [o for o in deer.all_objects if o.parent is None]
    for o in deer_objs:
        o.location = Vector(o.location) + Vector((0.0, 3.2, 0.35))
    cam = bpy.data.cameras.new("cam")
    cam.lens = 35
    co = link(bpy.data.objects.new("cam", cam))
    scn.camera = co
    shots = {"three_quarter": ((4.6, -3.4, 2.4), (0, 0.8, 0.4)), "side": ((6.5, 1.2, 1.2), (0, 1.3, 0.3)),
             "front_face": ((1.4, 2.6, 1.4), (0, 0.0, 1.0))}
    for nm, (pos, tgt) in shots.items():
        co.location = pos
        d = Vector(tgt) - Vector(pos)
        co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = os.path.join(PREVIEW, nm + ".png")
        bpy.ops.render.render(write_still=True)
        print("preview", scn.render.filepath)
