from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

SCALE = 3
WIDTH, HEIGHT = 1200, 630
PAPER = "#f0efe9"
INK = "#20201e"
CORAL = "#ff6046"
FONT_FILE = Path(__file__).parent / "dist/assets/fonts/InstrumentSans-latin.woff2"


def font(size, weight):
    face = ImageFont.truetype(FONT_FILE, size * SCALE)
    face.set_variation_by_axes([weight])
    return face


def text(draw, xy, content, size, weight, fill):
    draw.text((xy[0] * SCALE, xy[1] * SCALE), content,
              font=font(size, weight), fill=fill, anchor="lt")


image = Image.new("RGB", (WIDTH * SCALE, HEIGHT * SCALE), PAPER)
draw = ImageDraw.Draw(image)

# The mark and two-line headline follow the supplied composition, with
# generous edges for the 1.91:1 social card crop.
text(draw, (45, 43), "typefield", 60, 700, INK)
mark_x = 45 + font(60, 700).getlength("typefield") / SCALE + 4
text(draw, (mark_x, 45), "™", 18, 700, INK)
text(draw, (46, 232), "Quite the", 204, 600, INK)
text(draw, (46, 421), "character", 204, 600, INK)
headline_font = font(204, 600)
period_x = 46 + headline_font.getlength("character") / SCALE - 5
word_height = headline_font.getbbox("character", anchor="lt")[3] / SCALE
period_height = headline_font.getbbox(".", anchor="lt")[3] / SCALE
text(draw, (period_x, 421 + word_height - period_height), ".", 204, 600, CORAL)

output = (Path(sys.argv[1]) if len(sys.argv) > 1
          else Path(__file__).parent / "dist/assets/social-preview-v2.png")
output.parent.mkdir(parents=True, exist_ok=True)
image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).save(output, optimize=True)
