extends RefCounted
## THE elf size. Everything sized by the elf (speeds, camera, ranges, darts, magnet, trolley, noise,
## notice distance, Crook-Line, cutscene framing) is written in elf heights ("eh") and converted
## here, so changing ELF_HEIGHT rescales the whole stealth game, including the three furniture
## gap tiers below (crawl-only, crouch-fit, stand-under).

const ELF_HEIGHT := 0.22  ## THE constant. Standing elf, shoes to hat tip (m). About ankle-to-shin on an adult.
const CROUCH_EH := 0.5  ## Crawling (hat squashed) collision height in elf heights -> 0.11 m.
const TAC_CROUCH_EH := 0.75  ## Tactical crouch (crouch-walk) collision height, eh -> 0.165 m.
const STAND_CAPSULE_EH := 0.92  ## Standing collision height, eh -> 0.202 m (the floppy hat tip is soft).
## Furniture height tiers: the gap under couches, armchairs, beds, wardrobes, TV units, coffee and
## side tables is one of these (picked at random per piece, seeded per house):
const GAP_LOW_EH := 0.62  ## crawl-only (0.136 m): crawl 0.5 fits, crouch 0.75 doesn't
const GAP_MID_EH := 0.85  ## crouch-fit (0.187 m): crouch 0.75 fits, standing 0.92 doesn't
const GAP_HIGH_EH := 1.15  ## stand-under (0.253 m): standing 0.92 fits
const RADIUS_EH := 0.23  ## Collision capsule radius in elf heights -> 0.05 m.
const MODEL_HEIGHT := 0.62  ## Height of elf.glb as modelled in build_models.py (hat tip, m).


## Elf heights -> metres.
static func m(eh: float) -> float:
	return eh * ELF_HEIGHT


static func crouch_height() -> float:
	return CROUCH_EH * ELF_HEIGHT


static func tac_crouch_height() -> float:
	return TAC_CROUCH_EH * ELF_HEIGHT


static func stand_height() -> float:
	return STAND_CAPSULE_EH * ELF_HEIGHT


static func radius() -> float:
	return RADIUS_EH * ELF_HEIGHT
