"""Generate the geometric application icon (requires Pillow)."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
assets = root / "app/Blockyees/Resources/Assets.xcassets"
target = assets / "AppIcon.appiconset"
target.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), "#123E41")
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((247, 166, 841, 883), radius=65, fill="#28666A")
draw.rounded_rectangle((190, 130, 784, 847), radius=65, fill="#F5F0E4")
draw.rounded_rectangle((190, 130, 302, 847), radius=35, fill="#D8E4DC")
draw.rectangle((258, 130, 302, 847), fill="#D8E4DC")
draw.rounded_rectangle((355, 281, 655, 333), radius=26, fill="#246366")
draw.rounded_rectangle((355, 399, 673, 451), radius=26, fill="#246366")
draw.rounded_rectangle((355, 517, 575, 569), radius=26, fill="#246366")
draw.polygon(((633, 130), (711, 130), (711, 297), (672, 269), (633, 297)), fill="#E8AB65")
image.save(target / "AppIcon.png")
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
(target / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
