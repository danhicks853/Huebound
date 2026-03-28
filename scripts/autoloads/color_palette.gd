extends Node

signal color_discovered(palette_index: int, color_name: String, color: Color, bonus_value: float)

# 256 curated colors — value based on spectral distance from the 3 primaries
# Primaries (Blue, Red, Yellow) are worth 1-3
# All others valued 1-256 based on how far they are from the nearest primary

const PRIMARY_COLORS := [
	Color8(0, 0, 255),   # Blue
	Color8(255, 0, 0),   # Red
	Color8(255, 255, 0), # Yellow
]
const MAX_COLOR_VALUE := 10.0

# Each entry: {name, color (Color), tier, value, recipe}
var palette: Array[Dictionary] = []
var discovered: Array[bool] = []
var discovery_count: int = 0

func _ready() -> void:
	_build_palette()
	_validate_unique_recipes()
	discovered.resize(palette.size())
	discovered.fill(false)

func _build_palette() -> void:
	# Tier 0: Pure primaries (3) — no recipe
	_add("Blue", Color8(0, 0, 255), 0)
	_add("Red", Color8(255, 0, 0), 0)
	_add("Yellow", Color8(255, 255, 0), 0)
	
	# Tier 1: Secondaries - direct mixes of 2 primaries (6)
	_add("Purple", Color8(128, 0, 128), 1, ["Red", "Blue"])
	_add("Orange", Color8(255, 128, 0), 1, ["Red", "Yellow"])
	_add("Green", Color8(128, 255, 0), 1, ["Blue", "Yellow"])
	_add("Violet", Color8(128, 0, 255), 1, ["Blue", "Blue"])
	_add("Rose", Color8(255, 0, 128), 1, ["Red", "Red"])
	_add("Chartreuse", Color8(223, 255, 0), 1, ["Yellow", "Yellow"])
	
	# Tier 2: Tertiaries - primary + secondary (24)
	_add("Magenta", Color8(192, 0, 192), 2, ["Red", "Purple"])
	_add("Indigo", Color8(64, 0, 192), 2, ["Blue", "Purple"])
	_add("Vermillion", Color8(192, 64, 0), 2, ["Red", "Orange"])
	_add("Scarlet", Color8(255, 32, 0), 2, ["Rose", "Orange"])
	_add("Crimson", Color8(220, 20, 60), 2, ["Red", "Rose"])
	_add("Coral", Color8(255, 96, 64), 2, ["Scarlet", "Yellow"])
	_add("Salmon", Color8(250, 128, 114), 2, ["Rose", "Yellow"])
	_add("Amber", Color8(255, 192, 0), 2, ["Orange", "Yellow"])
	_add("Gold", Color8(255, 215, 0), 2, ["Amber", "Yellow"])
	_add("Lime", Color8(192, 255, 0), 2, ["Yellow", "Green"])
	_add("Teal", Color8(0, 128, 128), 2, ["Blue", "Green"])
	_add("Cyan", Color8(0, 255, 255), 2, ["Green", "Violet"])
	_add("Sky", Color8(64, 128, 255), 2, ["Blue", "Violet"])
	_add("Azure", Color8(0, 128, 255), 2, ["Violet", "Teal"])
	_add("Cerulean", Color8(0, 64, 192), 2, ["Blue", "Teal"])
	_add("Lavender", Color8(192, 128, 255), 2, ["Purple", "Violet"])
	_add("Plum", Color8(192, 64, 192), 2, ["Purple", "Rose"])
	_add("Fuchsia", Color8(255, 0, 192), 2, ["Magenta", "Rose"])
	_add("Hot Pink", Color8(255, 64, 192), 2, ["Fuchsia", "Rose"])
	_add("Peach", Color8(255, 192, 128), 2, ["Orange", "Chartreuse"])
	_add("Apricot", Color8(255, 192, 96), 2, ["Amber", "Rose"])
	_add("Mint", Color8(128, 255, 192), 2, ["Green", "Chartreuse"])
	_add("Spring", Color8(0, 255, 128), 2, ["Lime", "Blue"])
	_add("Emerald", Color8(0, 192, 64), 2, ["Green", "Teal"])
	
	# Tier 3: Quaternaries - secondary+secondary, more complex mixes (48)
	_add("Mauve", Color8(224, 176, 255), 3, ["Lavender", "Rose"])
	_add("Periwinkle", Color8(128, 128, 255), 3, ["Blue", "Lavender"])
	_add("Iris", Color8(96, 64, 192), 3, ["Indigo", "Violet"])
	_add("Amethyst", Color8(153, 102, 204), 3, ["Purple", "Lavender"])
	_add("Orchid", Color8(218, 112, 214), 3, ["Magenta", "Lavender"])
	_add("Thistle", Color8(216, 191, 216), 3, ["Lavender", "Peach"])
	_add("Lilac", Color8(200, 162, 200), 3, ["Lavender", "Plum"])
	_add("Wine", Color8(114, 47, 55), 3, ["Crimson", "Purple"])
	_add("Burgundy", Color8(128, 0, 32), 3, ["Red", "Plum"])
	_add("Maroon", Color8(128, 0, 0), 3, ["Red", "Crimson"])
	_add("Rust", Color8(183, 65, 14), 3, ["Vermillion", "Orange"])
	_add("Sienna", Color8(160, 82, 45), 3, ["Orange", "Crimson"])
	_add("Copper", Color8(184, 115, 51), 3, ["Orange", "Amber"])
	_add("Bronze", Color8(205, 127, 50), 3, ["Amber", "Vermillion"])
	_add("Brass", Color8(181, 166, 66), 3, ["Orange", "Green"])
	_add("Olive", Color8(128, 128, 0), 3, ["Yellow", "Teal"])
	_add("Moss", Color8(96, 128, 0), 3, ["Lime", "Teal"])
	_add("Forest", Color8(34, 139, 34), 3, ["Green", "Emerald"])
	_add("Jade", Color8(0, 168, 107), 3, ["Emerald", "Teal"])
	_add("Sage", Color8(176, 208, 176), 3, ["Mint", "Peach"])
	_add("Sea Green", Color8(46, 139, 87), 3, ["Emerald", "Spring"])
	_add("Turquoise", Color8(64, 224, 208), 3, ["Cyan", "Green"])
	_add("Aquamarine", Color8(127, 255, 212), 3, ["Cyan", "Mint"])
	_add("Steel", Color8(70, 130, 180), 3, ["Azure", "Teal"])
	_add("Slate", Color8(112, 128, 144), 3, ["Teal", "Indigo"])
	_add("Denim", Color8(21, 96, 189), 3, ["Blue", "Azure"])
	_add("Navy", Color8(0, 0, 128), 3, ["Indigo", "Blue"])
	_add("Midnight", Color8(25, 25, 112), 3, ["Purple", "Indigo"])
	_add("Cobalt", Color8(0, 71, 171), 3, ["Azure", "Indigo"])
	_add("Sapphire", Color8(15, 82, 186), 3, ["Azure", "Violet"])
	_add("Raspberry", Color8(227, 11, 93), 3, ["Crimson", "Rose"])
	_add("Ruby", Color8(224, 17, 95), 3, ["Crimson", "Magenta"])
	_add("Garnet", Color8(115, 54, 53), 3, ["Vermillion", "Purple"])
	_add("Brick", Color8(203, 65, 84), 3, ["Red", "Coral"])
	_add("Terracotta", Color8(204, 78, 92), 3, ["Coral", "Crimson"])
	_add("Clay", Color8(183, 110, 121), 3, ["Coral", "Purple"])
	_add("Blush", Color8(222, 93, 131), 3, ["Rose", "Coral"])
	_add("Flamingo", Color8(252, 142, 172), 3, ["Rose", "Apricot"])
	_add("Bubblegum", Color8(255, 193, 204), 3, ["Rose", "Peach"])
	_add("Tangerine", Color8(255, 159, 0), 3, ["Orange", "Gold"])
	_add("Pumpkin", Color8(255, 117, 24), 3, ["Vermillion", "Yellow"])
	_add("Honey", Color8(235, 177, 52), 3, ["Amber", "Gold"])
	_add("Lemon", Color8(255, 247, 0), 3, ["Chartreuse", "Gold"])
	_add("Canary", Color8(255, 239, 0), 3, ["Chartreuse", "Amber"])
	_add("Pistachio", Color8(147, 197, 114), 3, ["Green", "Lime"])
	_add("Seafoam", Color8(159, 226, 191), 3, ["Mint", "Spring"])
	_add("Powder", Color8(176, 224, 230), 3, ["Cyan", "Lavender"])
	_add("Ice", Color8(160, 210, 235), 3, ["Cyan", "Sky"])
	
	# Tier 4: Complex - exotic mixes requiring 3+ steps (96)
	_add("Ash", Color8(178, 190, 181), 4, ["Sage", "Slate"])
	_add("Pewter", Color8(150, 169, 176), 4, ["Steel", "Slate"])
	_add("Silver", Color8(192, 192, 192), 4, ["Sage", "Powder"])
	_add("Platinum", Color8(229, 228, 226), 4, ["Silver", "Cream"])
	_add("Pearl", Color8(234, 224, 200), 4, ["Silver", "Peach"])
	_add("Ivory", Color8(255, 255, 240), 4, ["Chartreuse", "Peach"])
	_add("Cream", Color8(255, 253, 208), 4, ["Yellow", "Peach"])
	_add("Vanilla", Color8(243, 229, 171), 4, ["Gold", "Peach"])
	_add("Wheat", Color8(245, 222, 179), 4, ["Honey", "Peach"])
	_add("Sand", Color8(194, 178, 128), 4, ["Honey", "Olive"])
	_add("Tan", Color8(210, 180, 140), 4, ["Wheat", "Peach"])
	_add("Khaki", Color8(195, 176, 145), 4, ["Sand", "Peach"])
	_add("Camel", Color8(193, 154, 107), 4, ["Honey", "Sienna"])
	_add("Taupe", Color8(72, 60, 50), 4, ["Sienna", "Slate"])
	_add("Umber", Color8(99, 81, 71), 4, ["Sienna", "Garnet"])
	_add("Sepia", Color8(112, 66, 20), 4, ["Sienna", "Orange"])
	_add("Chocolate", Color8(123, 63, 0), 4, ["Sienna", "Red"])
	_add("Mocha", Color8(111, 78, 55), 4, ["Sienna", "Copper"])
	_add("Coffee", Color8(101, 67, 50), 4, ["Copper", "Garnet"])
	_add("Chestnut", Color8(149, 69, 53), 4, ["Rust", "Garnet"])
	_add("Mahogany", Color8(192, 54, 10), 4, ["Rust", "Red"])
	_add("Auburn", Color8(165, 42, 42), 4, ["Maroon", "Sienna"])
	_add("Cinnamon", Color8(210, 105, 30), 4, ["Orange", "Rust"])
	_add("Ginger", Color8(176, 101, 0), 4, ["Copper", "Rust"])
	_add("Caramel", Color8(255, 213, 128), 4, ["Apricot", "Gold"])
	_add("Butterscotch", Color8(228, 149, 0), 4, ["Tangerine", "Gold"])
	_add("Marigold", Color8(234, 162, 33), 4, ["Gold", "Honey"])
	_add("Saffron", Color8(244, 196, 48), 4, ["Gold", "Canary"])
	_add("Mustard", Color8(255, 219, 88), 4, ["Gold", "Yellow"])
	_add("Flax", Color8(238, 220, 130), 4, ["Gold", "Cream"])
	_add("Champagne", Color8(247, 231, 206), 4, ["Peach", "Cream"])
	_add("Bone", Color8(227, 218, 201), 4, ["Cream", "Sand"])
	_add("Linen", Color8(250, 240, 230), 4, ["Cream", "Apricot"])
	_add("Parchment", Color8(252, 248, 232), 4, ["Cream", "Ivory"])
	_add("Eggshell", Color8(240, 234, 214), 4, ["Cream", "Vanilla"])
	_add("Snow", Color8(255, 250, 250), 4, ["Ivory", "Powder"])
	_add("Ghost", Color8(248, 248, 255), 4, ["Snow", "Lavender"])
	_add("Fog", Color8(220, 220, 230), 4, ["Silver", "Powder"])
	_add("Mist", Color8(200, 210, 220), 4, ["Powder", "Steel"])
	_add("Storm", Color8(100, 110, 130), 4, ["Slate", "Cobalt"])
	_add("Thunder", Color8(75, 80, 100), 4, ["Storm", "Navy"])
	_add("Shadow", Color8(50, 50, 60), 4, ["Navy", "Midnight"])
	_add("Charcoal", Color8(54, 69, 79), 4, ["Slate", "Navy"])
	_add("Graphite", Color8(56, 56, 60), 4, ["Charcoal", "Navy"])
	_add("Onyx", Color8(53, 56, 57), 4, ["Navy", "Forest"])
	_add("Obsidian", Color8(28, 32, 36), 4, ["Navy", "Navy"])
	_add("Ink", Color8(20, 20, 40), 4, ["Midnight", "Cobalt"])
	_add("Void", Color8(10, 10, 20), 4, ["Obsidian", "Midnight"])
	_add("Raven", Color8(30, 30, 45), 4, ["Midnight", "Charcoal"])
	_add("Eclipse", Color8(40, 20, 60), 4, ["Midnight", "Purple"])
	_add("Dusk", Color8(80, 60, 100), 4, ["Iris", "Midnight"])
	_add("Twilight", Color8(100, 80, 140), 4, ["Amethyst", "Indigo"])
	_add("Dawn", Color8(255, 200, 160), 4, ["Peach", "Salmon"])
	_add("Sunrise", Color8(255, 180, 100), 4, ["Peach", "Orange"])
	_add("Sunset", Color8(250, 128, 80), 4, ["Orange", "Coral"])
	_add("Ember", Color8(200, 60, 20), 4, ["Rust", "Maroon"])
	_add("Flame", Color8(255, 80, 0), 4, ["Vermillion", "Scarlet"])
	_add("Lava", Color8(207, 16, 32), 4, ["Maroon", "Vermillion"])
	_add("Blood", Color8(138, 7, 7), 4, ["Burgundy", "Maroon"])
	_add("Cherry", Color8(222, 49, 99), 4, ["Raspberry", "Rose"])
	_add("Strawberry", Color8(252, 90, 141), 4, ["Blush", "Coral"])
	_add("Watermelon", Color8(252, 108, 133), 4, ["Flamingo", "Salmon"])
	_add("Cotton Candy", Color8(255, 188, 217), 4, ["Bubblegum", "Lavender"])
	_add("Rose Quartz", Color8(170, 152, 169), 4, ["Lilac", "Clay"])
	_add("Wisteria", Color8(201, 160, 220), 4, ["Lavender", "Orchid"])
	_add("Heather", Color8(181, 148, 180), 4, ["Lilac", "Slate"])
	_add("Grape", Color8(111, 45, 168), 4, ["Purple", "Iris"])
	_add("Eggplant", Color8(97, 64, 81), 4, ["Purple", "Garnet"])
	_add("Mulberry", Color8(197, 75, 140), 4, ["Hot Pink", "Wine"])
	_add("Boysenberry", Color8(135, 50, 96), 4, ["Plum", "Garnet"])
	_add("Claret", Color8(127, 23, 52), 4, ["Burgundy", "Rose"])
	_add("Oxblood", Color8(74, 2, 2), 4, ["Blood", "Burgundy"])
	_add("Pine", Color8(1, 121, 111), 4, ["Teal", "Forest"])
	_add("Fern", Color8(79, 121, 66), 4, ["Forest", "Moss"])
	_add("Clover", Color8(0, 128, 64), 4, ["Spring", "Forest"])
	_add("Basil", Color8(88, 130, 72), 4, ["Forest", "Olive"])
	_add("Avocado", Color8(86, 130, 3), 4, ["Green", "Olive"])
	_add("Pear", Color8(209, 226, 49), 4, ["Lime", "Yellow"])
	_add("Celery", Color8(180, 210, 100), 4, ["Lime", "Pistachio"])
	_add("Eucalyptus", Color8(95, 133, 117), 4, ["Teal", "Sage"])
	_add("Ocean", Color8(0, 105, 148), 4, ["Cerulean", "Teal"])
	_add("Marine", Color8(0, 80, 120), 4, ["Denim", "Teal"])
	_add("Lagoon", Color8(0, 140, 160), 4, ["Teal", "Cyan"])
	_add("Arctic", Color8(130, 200, 230), 4, ["Cyan", "Powder"])
	_add("Glacier", Color8(96, 130, 182), 4, ["Steel", "Azure"])
	_add("Cornflower", Color8(100, 149, 237), 4, ["Sky", "Azure"])
	_add("Bluebell", Color8(63, 63, 175), 4, ["Periwinkle", "Navy"])
	_add("Hyacinth", Color8(120, 100, 190), 4, ["Indigo", "Lavender"])
	_add("Violet Blue", Color8(76, 40, 130), 4, ["Iris", "Navy"])
	_add("Royal", Color8(65, 105, 225), 4, ["Blue", "Sky"])
	_add("Imperial", Color8(96, 0, 128), 4, ["Purple", "Navy"])
	_add("Regal", Color8(80, 32, 128), 4, ["Midnight", "Magenta"])
	_add("Majesty", Color8(116, 40, 148), 4, ["Purple", "Magenta"])
	_add("Crown", Color8(200, 170, 50), 4, ["Gold", "Olive"])
	_add("Topaz", Color8(255, 200, 124), 4, ["Peach", "Amber"])
	_add("Citrine", Color8(228, 208, 10), 4, ["Mustard", "Lime"])
	_add("Peridot", Color8(180, 210, 0), 4, ["Lime", "Chartreuse"])
	
	# Tier 5: Rare - very specific mixes (fill to 256)
	_add("Nebula", Color8(120, 40, 180), 5, ["Indigo", "Grape"])
	_add("Cosmos", Color8(60, 20, 100), 5, ["Eclipse", "Indigo"])
	_add("Aurora", Color8(100, 255, 180), 5, ["Mint", "Green"])
	_add("Prism", Color8(200, 200, 255), 5, ["Lavender", "Powder"])
	_add("Opal", Color8(168, 195, 188), 5, ["Sage", "Ice"])
	_add("Moonstone", Color8(200, 200, 220), 5, ["Silver", "Fog"])
	_add("Sunstone", Color8(240, 180, 80), 5, ["Gold", "Sunrise"])
	_add("Starlight", Color8(230, 230, 250), 5, ["Ghost", "Prism"])
	_add("Comet", Color8(150, 160, 200), 5, ["Periwinkle", "Steel"])
	_add("Meteor", Color8(180, 80, 40), 5, ["Rust", "Ember"])
	_add("Supernova", Color8(255, 200, 200), 5, ["Salmon", "Bubblegum"])
	_add("Quasar", Color8(100, 60, 200), 5, ["Indigo", "Iris"])
	_add("Pulsar", Color8(60, 200, 255), 5, ["Ice", "Azure"])
	_add("Neutron", Color8(180, 180, 200), 5, ["Fog", "Slate"])
	_add("Plasma", Color8(160, 255, 200), 5, ["Mint", "Seafoam"])
	_add("Ether", Color8(200, 220, 255), 5, ["Powder", "Ghost"])
	_add("Aether", Color8(220, 200, 255), 5, ["Lavender", "Prism"])
	_add("Mirage", Color8(180, 160, 200), 5, ["Lilac", "Periwinkle"])
	_add("Phantom", Color8(100, 100, 120), 5, ["Slate", "Storm"])
	_add("Specter", Color8(140, 130, 160), 5, ["Heather", "Storm"])
	_add("Wraith", Color8(80, 80, 100), 5, ["Storm", "Shadow"])
	_add("Shade", Color8(60, 60, 80), 5, ["Shadow", "Midnight"])
	_add("Gloom", Color8(40, 40, 60), 5, ["Shadow", "Navy"])
	_add("Abyss", Color8(15, 15, 30), 5, ["Void", "Ink"])
	_add("Zenith", Color8(240, 240, 255), 5, ["Ghost", "Snow"])
	_add("Apex", Color8(255, 230, 200), 5, ["Champagne", "Dawn"])
	_add("Pinnacle", Color8(255, 245, 230), 5, ["Linen", "Snow"])
	_add("Summit", Color8(200, 220, 240), 5, ["Mist", "Powder"])
	_add("Horizon", Color8(180, 140, 200), 5, ["Lilac", "Amethyst"])
	_add("Solstice", Color8(255, 160, 80), 5, ["Sunset", "Orange"])
	_add("Equinox", Color8(128, 128, 160), 5, ["Slate", "Periwinkle"])
	_add("Tempest", Color8(60, 80, 120), 5, ["Thunder", "Charcoal"])
	_add("Zephyr", Color8(160, 200, 180), 5, ["Seafoam", "Pistachio"])
	_add("Nimbus", Color8(180, 190, 210), 5, ["Mist", "Fog"])
	_add("Cirrus", Color8(210, 220, 240), 5, ["Fog", "Powder"])
	_add("Stratus", Color8(170, 180, 200), 5, ["Mist", "Steel"])
	_add("Cumulus", Color8(230, 235, 240), 5, ["Fog", "Snow"])
	_add("Haze", Color8(190, 180, 170), 5, ["Sand", "Silver"])
	_add("Smog", Color8(140, 130, 120), 5, ["Slate", "Sand"])
	_add("Dust", Color8(180, 160, 140), 5, ["Sand", "Tan"])
	_add("Soot", Color8(60, 50, 40), 5, ["Taupe", "Shadow"])
	_add("Cinder", Color8(100, 60, 30), 5, ["Sepia", "Umber"])
	_add("Ash Rose", Color8(180, 130, 130), 5, ["Clay", "Salmon"])
	_add("Dusty Rose", Color8(200, 150, 150), 5, ["Salmon", "Blush"])
	_add("Antique", Color8(205, 185, 162), 5, ["Tan", "Champagne"])
	_add("Patina", Color8(120, 160, 140), 5, ["Eucalyptus", "Sage"])
	_add("Verdigris", Color8(67, 179, 174), 5, ["Teal", "Turquoise"])
	_add("Oxidized", Color8(100, 140, 120), 5, ["Eucalyptus", "Forest"])
	_add("Tarnish", Color8(140, 130, 100), 5, ["Olive", "Sand"])
	_add("Lichen", Color8(130, 160, 100), 5, ["Moss", "Pistachio"])
	_add("Moss Agate", Color8(100, 140, 80), 5, ["Fern", "Olive"])
	_add("Malachite", Color8(0, 120, 80), 5, ["Jade", "Pine"])
	_add("Lapis", Color8(38, 97, 156), 5, ["Azure", "Cobalt"])
	_add("Tanzanite", Color8(69, 69, 155), 5, ["Indigo", "Navy"])
	_add("Alexandrite", Color8(100, 80, 120), 5, ["Dusk", "Slate"])
	_add("Tourmaline", Color8(134, 60, 100), 5, ["Boysenberry", "Garnet"])
	_add("Garnet Rose", Color8(160, 50, 70), 5, ["Burgundy", "Brick"])
	_add("Carnelian", Color8(179, 27, 27), 5, ["Ember", "Burgundy"])
	_add("Jasper", Color8(215, 59, 62), 5, ["Red", "Brick"])
	_add("Agate", Color8(180, 140, 100), 5, ["Copper", "Sand"])
	_add("Amber Glow", Color8(255, 180, 50), 5, ["Saffron", "Orange"])
	_add("Tiger Eye", Color8(180, 120, 20), 5, ["Sienna", "Gold"])
	_add("Sandstone", Color8(220, 190, 150), 5, ["Tan", "Peach"])
	_add("Terracotta Sun", Color8(220, 120, 80), 5, ["Coral", "Rust"])
	_add("Adobe", Color8(189, 100, 67), 5, ["Sienna", "Coral"])
	_add("Paprika", Color8(142, 28, 0), 5, ["Ember", "Vermillion"])
	_add("Cayenne", Color8(148, 18, 18), 5, ["Blood", "Ember"])
	_add("Tabasco", Color8(168, 40, 10), 5, ["Red", "Ember"])
	_add("Habanero", Color8(255, 100, 0), 5, ["Flame", "Orange"])
	_add("Mango", Color8(255, 130, 67), 5, ["Tangerine", "Coral"])
	_add("Papaya", Color8(255, 164, 100), 5, ["Apricot", "Sunrise"])
	_add("Guava", Color8(255, 140, 148), 5, ["Salmon", "Rose"])
	_add("Dragonfruit", Color8(200, 60, 100), 5, ["Raspberry", "Blush"])
	_add("Acai", Color8(75, 0, 110), 5, ["Grape", "Midnight"])
	_add("Elderberry", Color8(60, 0, 80), 5, ["Imperial", "Navy"])
	_add("Blackberry", Color8(80, 20, 80), 5, ["Purple", "Wine"])
	_add("Plum Wine", Color8(100, 30, 60), 5, ["Wine", "Burgundy"])
	_add("Fig", Color8(80, 40, 60), 5, ["Wine", "Eggplant"])
	_add("Raisin", Color8(60, 30, 40), 5, ["Wine", "Shadow"])

func _validate_unique_recipes() -> void:
	var seen: Dictionary = {}  # sorted recipe key -> color name
	var dupes := 0
	for entry in palette:
		var recipe: Array = entry.recipe
		if recipe.size() == 0:
			continue
		var sorted_r: Array = recipe.duplicate()
		sorted_r.sort()
		var key = "+".join(sorted_r)
		if seen.has(key):
			push_warning("[ColorPalette] DUPLICATE RECIPE: '%s' and '%s' both use %s" % [seen[key], entry.name, key])
			dupes += 1
		else:
			seen[key] = entry.name
	if dupes == 0:
		print("[ColorPalette] All %d recipes are unique." % seen.size())
	else:
		push_warning("[ColorPalette] Found %d duplicate recipes!" % dupes)

func _add(color_name: String, color: Color, tier: int, recipe: Array = []) -> void:
	var value = _calc_color_value(color)
	palette.append({
		"name": color_name,
		"color": color,
		"tier": tier,
		"value": value,
		"recipe": recipe,
	})

func _calc_color_value(color: Color) -> float:
	# Find minimum RGB distance to any primary
	var min_dist := 999999.0
	for primary in PRIMARY_COLORS:
		var dr = (color.r - primary.r) * 255.0
		var dg = (color.g - primary.g) * 255.0
		var db = (color.b - primary.b) * 255.0
		var dist = sqrt(dr * dr + dg * dg + db * db)
		if dist < min_dist:
			min_dist = dist
	# Max possible distance in RGB space is ~441 (corner to corner)
	# Sqrt curve keeps values low early, gentle ramp for exotic colors
	var normalized = clampf(min_dist / 441.0, 0.0, 1.0)
	return maxf(1.0, round(sqrt(normalized) * MAX_COLOR_VALUE))

func get_palette_size() -> int:
	return palette.size()

func find_nearest_color(color: Color) -> int:
	var best_index := 0
	var best_dist := 999999.0
	for i in range(palette.size()):
		var pc = palette[i].color
		var dr = (color.r - pc.r) * 255.0
		var dg = (color.g - pc.g) * 255.0
		var db = (color.b - pc.b) * 255.0
		var dist = dr * dr + dg * dg + db * db
		if dist < best_dist:
			best_dist = dist
			best_index = i
	return best_index

func get_color_value(color: Color) -> float:
	var idx = find_nearest_color(color)
	return palette[idx].value

func get_color_name(color: Color) -> String:
	var idx = find_nearest_color(color)
	return palette[idx].name

func sell_color(color: Color, _source_colors: Array = []) -> Dictionary:
	var idx = find_nearest_color(color)
	var entry = palette[idx]
	# In demo mode, non-demo colors can't be discovered
	var demo_blocked = DemoConfig.is_demo() and not DemoConfig.is_color_in_demo(entry.name)
	var is_new = not discovered[idx] and not demo_blocked
	var bonus = entry.value * 2.0 if is_new else 0.0
	if is_new:
		discovered[idx] = true
		discovery_count += 1
		color_discovered.emit(idx, entry.name, entry.color, bonus)
	return {
		"value": entry.value,
		"bonus": bonus,
		"total": entry.value + bonus,
		"palette_index": idx,
		"name": entry.name,
		"is_new": is_new,
	}

func lookup_recipe(input_names: Array[String]) -> int:
	# Given a set of input color names, find a palette entry whose recipe matches.
	# Order doesn't matter — ["Red", "Blue"] matches ["Blue", "Red"].
	# Returns palette index, or -1 if no recipe matches.
	var sorted_input = input_names.duplicate()
	sorted_input.sort()
	for i in range(palette.size()):
		var recipe: Array = palette[i].recipe
		if recipe.size() != sorted_input.size():
			continue
		var sorted_recipe: Array = recipe.duplicate()
		sorted_recipe.sort()
		var is_match := true
		for j in range(sorted_input.size()):
			if sorted_input[j] != sorted_recipe[j]:
				is_match = false
				break
		if is_match:
			return i
	return -1

func find_color_by_name(color_name: String) -> int:
	for i in range(palette.size()):
		if palette[i].name == color_name:
			return i
	return -1

func is_discovered(index: int) -> bool:
	if index < 0 or index >= discovered.size():
		return false
	return discovered[index]

func mix_colors(colors: Array) -> Color:
	if colors.is_empty():
		return Color.BLACK
	# Subtractive mixing via CMY: convert to CMY, average, convert back
	var c_total := 0.0
	var m_total := 0.0
	var y_total := 0.0
	for col in colors:
		c_total += 1.0 - col.r
		m_total += 1.0 - col.g
		y_total += 1.0 - col.b
	var n = float(colors.size())
	return Color(1.0 - c_total / n, 1.0 - m_total / n, 1.0 - y_total / n)
