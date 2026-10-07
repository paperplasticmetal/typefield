from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

SCALE = 3
WIDTH, HEIGHT = 1200, 630
PAPER = "#f0efe9"
INK = "#20201e"
CORAL = "#ff6046"
FONT_FILE = "/System/Library/Fonts/HelveticaNeue.ttc"


def font(size, face):
    return ImageFont.truetype(FONT_FILE, size * SCALE, index=face)


def text(draw, xy, content, size, face, fill):
    draw.text((xy[0] * SCALE, xy[1] * SCALE), content,
              font=font(size, face), fill=fill, anchor="lt")


image = Image.new("RGB", (WIDTH * SCALE, HEIGHT * SCALE), PAPER)
draw = ImageDraw.Draw(image)

# The mark and two-line headline follow the supplied composition, with
# generous edges for the 1.91:1 social card crop.
text(draw, (45, 43), "typefield", 60, 1, INK)
text(draw, (296, 45), "™", 18, 1, INK)
text(draw, (46, 232), "Quite the", 204, 10, INK)
text(draw, (46, 421), "character", 204, 10, INK)
headline_font = font(204, 10)
period_x = 46 + headline_font.getlength("character") / SCALE - 5
word_height = headline_font.getbbox("character", anchor="lt")[3] / SCALE
period_height = headline_font.getbbox(".", anchor="lt")[3] / SCALE
text(draw, (period_x, 421 + word_height - period_height), ".", 204, 10, CORAL)

output = (Path(sys.argv[1]) if len(sys.argv) > 1
          else Path(__file__).parent / "dist/assets/social-preview-v1.png")
output.parent.mkdir(parents=True, exist_ok=True)
image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).save(output, optimize=True)
