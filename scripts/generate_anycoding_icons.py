#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw

def render_icon(size, style="default", transparent=False, is_foreground_only=False, is_notification=False):
    """
    Renders the unified AnyCoding brand icon with 4x supersampling for high-fidelity anti-aliasing.
    """
    scale = 4
    ss = size * scale
    im = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    # Color palette
    if is_notification:
        orange_color = (255, 255, 255, 255)
        cyan_color = (255, 255, 255, 255)
        dot_color = (255, 255, 255, 255)
    elif style == "light_outline":
        orange_color = (248, 250, 252, 255) # White / slate 50
        cyan_color = (148, 163, 184, 255)   # Slate 400
        dot_color = (56, 189, 248, 255)     # Sky blue
    elif style == "pro_copper_emerald":
        orange_color = (245, 158, 11, 255)  # Amber / Copper #F59E0B
        cyan_color = (16, 185, 129, 255)    # Emerald #10B981
        dot_color = (56, 189, 248, 255)     # Sky blue
    else: # default
        orange_color = (255, 122, 0, 255)   # Warm Orange #FF7A00
        cyan_color = (0, 210, 180, 255)     # Codex Cyan #00D2B4
        dot_color = (56, 189, 248, 255)     # Sky blue #38BDF8

    # Base background (only for full launcher / preview icons)
    if not transparent and not is_foreground_only and not is_notification:
        bg_color = (11, 15, 25, 255) # Deep Navy #0B0F19
        radius = int(ss * 0.22)      # Continuous rounded squircle
        draw.rounded_rectangle([0, 0, ss - 1, ss - 1], radius=radius, fill=bg_color)

    # Coordinate mapping from 1024 space
    def pt(x, y):
        return (x * ss / 1024.0, y * ss / 1024.0)

    stroke_w = int(110.0 * ss / 1024.0)
    cap_r = stroke_w / 2.0

    # 1. Left ascending leg (Warm Orange): (280, 800) -> (512, 230)
    p_start = pt(280, 800)
    p_apex = pt(512, 230)
    draw.line([p_start, p_apex], fill=orange_color, width=stroke_w)
    draw.ellipse([p_start[0]-cap_r, p_start[1]-cap_r, p_start[0]+cap_r, p_start[1]+cap_r], fill=orange_color)
    draw.ellipse([p_apex[0]-cap_r, p_apex[1]-cap_r, p_apex[0]+cap_r, p_apex[1]+cap_r], fill=orange_color)

    # 2. Command Prompt Chevron / Transmission Trajectory: (400, 480) -> (760, 580) -> (512, 800)
    p_chev_start = pt(400, 480)
    p_chev_mid = pt(760, 580)
    p_chev_end = pt(512, 800)
    draw.line([p_chev_start, p_chev_mid], fill=cyan_color, width=stroke_w)
    draw.line([p_chev_mid, p_chev_end], fill=cyan_color, width=stroke_w)
    draw.ellipse([p_chev_start[0]-cap_r, p_chev_start[1]-cap_r, p_chev_start[0]+cap_r, p_chev_start[1]+cap_r], fill=cyan_color)
    draw.ellipse([p_chev_mid[0]-cap_r, p_chev_mid[1]-cap_r, p_chev_mid[0]+cap_r, p_chev_mid[1]+cap_r], fill=cyan_color)
    draw.ellipse([p_chev_end[0]-cap_r, p_chev_end[1]-cap_r, p_chev_end[0]+cap_r, p_chev_end[1]+cap_r], fill=cyan_color)

    # 3. Apex Pulse Execution Dot
    dot_r = 52.0 * ss / 1024.0
    draw.ellipse([p_apex[0]-dot_r, p_apex[1]-dot_r, p_apex[0]+dot_r, p_apex[1]+dot_r], fill=dot_color)

    # Downsample with Lanczos filter
    final_im = im.resize((size, size), Image.Resampling.LANCZOS)
    return final_im

def main():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    mobile_dir = os.path.join(base_dir, 'apps', 'mobile')
    assets_dir = os.path.join(mobile_dir, 'assets')
    res_dir = os.path.join(mobile_dir, 'android', 'app', 'src', 'main', 'res')

    print("Generating main Flutter assets...")
    # 1. assets/icon.png (1024x1024)
    im_main = render_icon(1024, style="default")
    im_main.save(os.path.join(assets_dir, 'icon.png'))

    # 2. assets/icon_foreground.png (1024x1024 transparent)
    im_fg = render_icon(1024, style="default", is_foreground_only=True)
    im_fg.save(os.path.join(assets_dir, 'icon_foreground.png'))

    # 3. assets/icon_notification.png (640x640 transparent monochrome)
    im_notif = render_icon(640, is_notification=True)
    im_notif.save(os.path.join(assets_dir, 'icon_notification.png'))

    # 4. assets/icon_light_outline.png (1024x1024)
    im_light = render_icon(1024, style="light_outline")
    im_light.save(os.path.join(assets_dir, 'icon_light_outline.png'))

    # 5. assets/icon_pro_copper_emerald.png (1024x1024)
    im_pro = render_icon(1024, style="pro_copper_emerald")
    im_pro.save(os.path.join(assets_dir, 'icon_pro_copper_emerald.png'))

    # Android mipmaps & drawables densities
    densities = {
        'mdpi': {'launcher': 48, 'fg': 108, 'notif': 24},
        'hdpi': {'launcher': 72, 'fg': 162, 'notif': 36},
        'xhdpi': {'launcher': 96, 'fg': 216, 'notif': 48},
        'xxhdpi': {'launcher': 144, 'fg': 324, 'notif': 72},
        'xxxhdpi': {'launcher': 192, 'fg': 432, 'notif': 96},
    }

    for density, sizes in densities.items():
        mipmap_path = os.path.join(res_dir, f'mipmap-{density}')
        drawable_path = os.path.join(res_dir, f'drawable-{density}')
        os.makedirs(mipmap_path, exist_ok=True)
        os.makedirs(drawable_path, exist_ok=True)

        l_size = sizes['launcher']
        # ic_launcher.png and launcher_icon.png
        im_l = render_icon(l_size, style="default")
        im_l.save(os.path.join(mipmap_path, 'ic_launcher.png'))
        im_l.save(os.path.join(mipmap_path, 'launcher_icon.png'))

        # Supporter icons
        render_icon(l_size, style="light_outline").save(os.path.join(mipmap_path, 'ic_launcher_supporter_light_outline.png'))
        render_icon(l_size, style="pro_copper_emerald").save(os.path.join(mipmap_path, 'ic_launcher_supporter_pro_copper_emerald.png'))

        fg_size = sizes['fg']
        render_icon(fg_size, style="default", is_foreground_only=True).save(os.path.join(drawable_path, 'ic_launcher_foreground.png'))
        render_icon(fg_size, style="light_outline", is_foreground_only=True).save(os.path.join(drawable_path, 'ic_launcher_supporter_light_outline_foreground.png'))
        render_icon(fg_size, style="pro_copper_emerald", is_foreground_only=True).save(os.path.join(drawable_path, 'ic_launcher_supporter_pro_copper_emerald_foreground.png'))

        n_size = sizes['notif']
        render_icon(n_size, is_notification=True).save(os.path.join(drawable_path, 'ic_notification.png'))

    print("All icon assets generated successfully!")

if __name__ == '__main__':
    main()
